use anyhow::{anyhow, Result};
use serde_json::Value as JsonValue;
use std::collections::HashMap;
use std::process::Stdio;
use std::sync::{Arc, Mutex as StdMutex};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, ChildStdin, Command};
use tokio::sync::{mpsc, oneshot, Mutex};

#[derive(Debug)]
pub enum AcpInbound {
    Notification { method: String, params: JsonValue },
    Request { id: u64, method: String, params: JsonValue },
}

#[derive(Clone)]
pub struct AcpClient {
    stdin: Arc<Mutex<ChildStdin>>,
    pending: Arc<StdMutex<HashMap<u64, oneshot::Sender<Result<JsonValue>>>>>,
    next_id: Arc<StdMutex<u64>>,
}

pub struct AcpConnection {
    pub client: AcpClient,
    pub child: Child,
    pub inbound_rx: Option<mpsc::UnboundedReceiver<AcpInbound>>,
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
        cmd.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::inherit());

        let mut child = cmd.spawn()?;
        let stdin = child.stdin.take().ok_or_else(|| anyhow!("missing stdin"))?;
        let stdout = child.stdout.take().ok_or_else(|| anyhow!("missing stdout"))?;

        let (inbound_tx, inbound_rx) = mpsc::unbounded_channel();
        let pending: Arc<StdMutex<HashMap<u64, oneshot::Sender<Result<JsonValue>>>>> =
            Arc::new(StdMutex::new(HashMap::new()));
        let pending_clone = pending.clone();

        tokio::spawn(async move {
            let mut reader = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                if line.trim().is_empty() {
                    continue;
                }
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
                        let _ = inbound_tx.send(AcpInbound::Request { id, method, params });
                    } else {
                        // response to our request
                        let result = if let Some(err) = value.get("error") {
                            Err(anyhow!("acp error: {err}"))
                        } else {
                            Ok(value.get("result").cloned().unwrap_or(JsonValue::Null))
                        };
                        if let Some(tx) = pending_clone.lock().unwrap().remove(&id) {
                            let _ = tx.send(result);
                        }
                    }
                } else if let Some(method) = value.get("method").and_then(|v| v.as_str()) {
                    let params = value.get("params").cloned().unwrap_or(JsonValue::Null);
                    let _ = inbound_tx.send(AcpInbound::Notification {
                        method: method.to_string(),
                        params,
                    });
                }
            }
        });

        let client = AcpClient {
            stdin: Arc::new(Mutex::new(stdin)),
            pending,
            next_id: Arc::new(StdMutex::new(1)),
        };

        Ok(AcpConnection {
            client,
            child,
            inbound_rx: Some(inbound_rx),
        })
    }

    pub async fn request(&self, method: &str, params: JsonValue) -> Result<JsonValue> {
        let msgid = {
            let mut next = self.next_id.lock().unwrap();
            let id = *next;
            *next += 1;
            id
        };

        let (tx, rx) = oneshot::channel();
        self.pending.lock().unwrap().insert(msgid, tx);

        let msg = serde_json::json!({
            "jsonrpc": "2.0",
            "id": msgid,
            "method": method,
            "params": params,
        });
        self.write_line(msg).await?;

        rx.await.map_err(|_| anyhow!("acp response dropped"))?
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
