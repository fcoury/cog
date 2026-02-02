use anyhow::{anyhow, Result};
use serde_json::Value as JsonValue;
use std::collections::HashMap;
use std::process::Stdio;
use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{ChildStdin, Command};
use tokio::sync::{mpsc, oneshot, Mutex};

#[derive(Debug)]
pub enum AcpInbound {
    Notification {
        method: String,
        params: JsonValue,
    },
    Request {
        id: u64,
        method: String,
        params: JsonValue,
    },
}

#[derive(Clone)]
pub struct AcpClient {
    stdin: Arc<Mutex<ChildStdin>>,
    pending: Arc<StdMutex<HashMap<u64, oneshot::Sender<Result<JsonValue>>>>>,
    next_id: Arc<StdMutex<u64>>,
}

pub struct AcpConnection {
    pub client: AcpClient,
    pub inbound_rx: Option<mpsc::UnboundedReceiver<AcpInbound>>,
    pub stderr_rx: Option<mpsc::UnboundedReceiver<String>>,
}

impl AcpClient {
    pub async fn spawn(
        command: Vec<String>,
        env: HashMap<String, String>,
        cwd: Option<String>,
    ) -> Result<AcpConnection> {
        let mut cmd = Command::new(&command[0]);
        if command.len() > 1 {
            cmd.args(&command[1..]);
        }
        if let Some(cwd) = cwd {
            cmd.current_dir(cwd);
        }
        if !env.is_empty() {
            cmd.envs(env);
        }
        cmd.stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        let mut child = cmd.spawn()?;
        let stdin = child.stdin.take().ok_or_else(|| anyhow!("missing stdin"))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| anyhow!("missing stdout"))?;
        let stderr = child
            .stderr
            .take()
            .ok_or_else(|| anyhow!("missing stderr"))?;

        let (inbound_tx, inbound_rx) = mpsc::unbounded_channel();
        let pending: Arc<StdMutex<HashMap<u64, oneshot::Sender<Result<JsonValue>>>>> =
            Arc::new(StdMutex::new(HashMap::new()));
        let pending_clone = pending.clone();

        // Capture stderr to report errors
        let (stderr_tx, stderr_rx) = mpsc::unbounded_channel::<String>();
        tokio::spawn(async move {
            let mut reader = BufReader::new(stderr).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                tracing::warn!("acp stderr: {line}");
                let _ = stderr_tx.send(line);
            }
        });

        // Read stdout and process messages
        tokio::spawn(async move {
            tracing::info!("ACP stdout reader started");
            let mut reader = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                if line.trim().is_empty() {
                    continue;
                }
                tracing::debug!("ACP stdout raw: {}", line);
                let parsed: Result<JsonValue> = serde_json::from_str(&line).map_err(|e| e.into());
                let value = match parsed {
                    Ok(v) => v,
                    Err(err) => {
                        tracing::warn!("acp parse error: {err}");
                        continue;
                    }
                };
                if let Some(id) = value.get("id").and_then(|v| v.as_u64()) {
                    if value.get("method").is_some() {
                        // request from agent
                        let method = value
                            .get("method")
                            .and_then(|v| v.as_str())
                            .unwrap_or("unknown")
                            .to_string();
                        let params = value.get("params").cloned().unwrap_or(JsonValue::Null);
                        tracing::info!("ACP request received: id={} method={}", id, method);
                        let _ = inbound_tx.send(AcpInbound::Request { id, method, params });
                    } else {
                        // response to our request
                        tracing::debug!("ACP response received: id={}", id);
                        let result = if let Some(err) = value.get("error") {
                            tracing::warn!("ACP response error: id={} err={}", id, err);
                            Err(anyhow!("acp error: {err}"))
                        } else {
                            Ok(value.get("result").cloned().unwrap_or(JsonValue::Null))
                        };
                        if let Some(tx) = pending_clone.lock().unwrap().remove(&id) {
                            let _ = tx.send(result);
                        } else {
                            tracing::warn!("ACP response for unknown id={} (no pending request)", id);
                        }
                    }
                } else if let Some(method) = value.get("method").and_then(|v| v.as_str()) {
                    let params = value.get("params").cloned().unwrap_or(JsonValue::Null);
                    tracing::info!("ACP notification received: method={}", method);
                    let _ = inbound_tx.send(AcpInbound::Notification {
                        method: method.to_string(),
                        params,
                    });
                } else {
                    tracing::warn!("ACP unknown message format: {:?}", value);
                }
            }
            tracing::warn!("ACP stdout reader exited - connection closed");
        });

        let client = AcpClient {
            stdin: Arc::new(Mutex::new(stdin)),
            pending,
            next_id: Arc::new(StdMutex::new(1)),
        };

        // Check if child exits early (indicates startup error)
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(500)).await;
            if let Ok(Some(status)) = child.try_wait() {
                tracing::error!("acp child exited early with status: {status}");
            }
        });

        Ok(AcpConnection {
            client,
            inbound_rx: Some(inbound_rx),
            stderr_rx: Some(stderr_rx),
        })
    }

    pub async fn request(&self, method: &str, params: JsonValue) -> Result<JsonValue> {
        let msgid = {
            let mut next = self.next_id.lock().unwrap();
            let id = *next;
            *next += 1;
            id
        };

        let (tx, mut rx) = oneshot::channel();
        self.pending.lock().unwrap().insert(msgid, tx);

        let msg = serde_json::json!({
            "jsonrpc": "2.0",
            "id": msgid,
            "method": method,
            "params": params,
        });
        self.write_line(msg).await?;

        // Use std::thread based timeout since tokio::time doesn't work under nvim
        // 30 second timeout to handle slow initial connections
        let (timeout_tx, timeout_rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_secs(30));
            let _ = timeout_tx.send(());
        });

        // Race between the response and the timeout
        let result = match rx.try_recv() {
            Ok(val) => val,
            Err(oneshot::error::TryRecvError::Empty) => {
                // Response not ready yet, wait for either response or timeout
                loop {
                    std::thread::sleep(std::time::Duration::from_millis(10));

                    // Check if response is ready
                    match rx.try_recv() {
                        Ok(val) => break val,
                        Err(oneshot::error::TryRecvError::Closed) => {
                            return Err(anyhow!(
                                "acp response channel closed - the ACP process may have exited"
                            ));
                        }
                        Err(oneshot::error::TryRecvError::Empty) => {
                            // Check timeout
                            if timeout_rx.try_recv().is_ok() {
                                let _ = self.pending.lock().unwrap().remove(&msgid);
                                return Err(anyhow!("request timed out after 30 seconds - the ACP process may have failed to start or exited unexpectedly"));
                            }
                        }
                    }
                }
            }
            Err(oneshot::error::TryRecvError::Closed) => {
                return Err(anyhow!(
                    "acp response channel closed - the ACP process may have exited"
                ));
            }
        };

        result
    }

    pub async fn notify(&self, method: &str, params: JsonValue) -> Result<()> {
        let msg = serde_json::json!({
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        });
        self.write_line(msg).await
    }

    pub async fn respond(&self, id: u64, result: Result<JsonValue>) -> Result<()> {
        let msg = match result {
            Ok(res) => serde_json::json!({
                "jsonrpc": "2.0",
                "id": id,
                "result": res,
            }),
            Err(err) => serde_json::json!({
                "jsonrpc": "2.0",
                "id": id,
                "error": {
                    "code": -32000,
                    "message": err.to_string(),
                }
            }),
        };
        self.write_line(msg).await
    }

    async fn write_line(&self, msg: JsonValue) -> Result<()> {
        let mut stdin = self.stdin.lock().await;
        let mut buf = serde_json::to_vec(&msg)?;
        buf.push(b'\n');
        stdin.write_all(&buf).await?;
        stdin.flush().await?;
        Ok(())
    }
}
