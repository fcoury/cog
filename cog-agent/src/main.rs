mod acp;
mod rpc;

use acp::{AcpClient, AcpConnection, AcpInbound};
use anyhow::{anyhow, Result};
use rpc::{as_single_param, parse_message, encode_response, RpcClient, RpcMessage};
use rmpv::Value;
use serde::Deserialize;
use serde_json::json;
use serde_json::Value as JsonValue;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{mpsc, oneshot, Mutex};
use tracing::Level;

#[derive(Debug, Deserialize)]
struct ConnectParams {
    command: Vec<String>,
    env: Option<HashMap<String, String>>,
    cwd: Option<String>,
    protocol_version: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SessionNewParams {
    cwd: Option<String>,
}

#[derive(Debug, Deserialize)]
struct PromptParams {
    session_id: String,
    content: String,
}

#[derive(Debug, Deserialize)]
struct CancelParams {
    session_id: String,
}

#[derive(Debug, Deserialize)]
struct PermissionResponseParams {
    request_id: u64,
    option_id: String,
}

#[derive(Debug, Deserialize)]
struct FileReadResponseParams {
    request_id: u64,
    content: String,
}

#[derive(Debug, Deserialize)]
struct FileWriteResponseParams {
    request_id: u64,
    success: bool,
    message: Option<String>,
}

#[derive(Clone)]
struct AppState {
    rpc: RpcClient,
    acp: Arc<Mutex<Option<AcpConnection>>>,
    pending_permission: Arc<Mutex<HashMap<u64, oneshot::Sender<String>>>>,
    pending_read: Arc<Mutex<HashMap<u64, oneshot::Sender<String>>>>,
    pending_write: Arc<Mutex<HashMap<u64, oneshot::Sender<Result<(), String>>>>>,
}

impl AppState {
    fn new(rpc: RpcClient) -> Self {
        Self {
            rpc,
            acp: Arc::new(Mutex::new(None)),
            pending_permission: Arc::new(Mutex::new(HashMap::new())),
            pending_read: Arc::new(Mutex::new(HashMap::new())),
            pending_write: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    async fn notify_lua(&self, event: &str, payload: JsonValue) {
        let code = "return require('cog.backend')._on_notify(...)";
        let args = vec![Value::from(event), json_to_rmpv(&payload)];
        let params = vec![Value::from(code), Value::Array(args)];
        let rx = self.rpc.request("nvim_exec_lua", params);
        tokio::spawn(async move {
            let _ = rx.await;
        });
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_max_level(Level::INFO)
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let (in_tx, mut in_rx) = mpsc::unbounded_channel();
    let (out_tx, out_rx) = mpsc::unbounded_channel();

    rpc::start_reader_thread(in_tx);
    rpc::start_writer_thread(out_rx);

    let rpc_client = RpcClient::new(out_tx.clone());
    let state = Arc::new(AppState::new(rpc_client.clone()));

    while let Some(val) = in_rx.recv().await {
        let msg = match parse_message(val) {
            Ok(msg) => msg,
            Err(err) => {
                tracing::warn!("invalid msgpack-rpc message: {err}");
                continue;
            }
        };

        match msg {
            RpcMessage::Response { msgid, error, result } => {
                rpc_client.handle_response(msgid, error, result);
            }
            RpcMessage::Notification { .. } => {
                // Not used
            }
            RpcMessage::Request {
                msgid,
                method,
                params,
            } => {
                let state_clone = state.clone();
                let tx = out_tx.clone();
                tokio::spawn(async move {
                    let result = handle_request(state_clone, method, params).await;
                    let response = match result {
                        Ok(val) => encode_response(msgid, None, Some(val)),
                        Err(err) => encode_response(
                            msgid,
                            Some(Value::Map(vec![(
                                Value::from("message"),
                                Value::from(err.to_string()),
                            )])),
                            None,
                        ),
                    };
                    let _ = tx.send(response);
                });
            }
        }
    }

    Ok(())
}

async fn handle_request(state: Arc<AppState>, method: String, params: Vec<Value>) -> Result<Value> {
    match method.as_str() {
        "cog_connect" => handle_connect(state, params).await,
        "cog_disconnect" => handle_disconnect(state).await,
        "cog_session_new" => handle_session_new(state, params).await,
        "cog_session_load" => handle_session_load(state, params).await,
        "cog_prompt" => handle_prompt(state, params).await,
        "cog_cancel" => handle_cancel(state, params).await,
        "cog_permission_respond" => handle_permission_response(state, params).await,
        "cog_file_read_response" => handle_file_read_response(state, params).await,
        "cog_file_write_response" => handle_file_write_response(state, params).await,
        _ => Err(anyhow!("unknown method {method}")),
    }
}

async fn handle_connect(state: Arc<AppState>, params: Vec<Value>) -> Result<Value> {
    let params: ConnectParams = as_single_param(params)?;
    if params.command.is_empty() {
        return Err(anyhow!("command is required"));
    }

    let env = params.env.unwrap_or_default();
    let mut connection = AcpClient::spawn(params.command, env, params.cwd).await?;
    let client = connection.client.clone();
    let inbound_rx = connection.inbound_rx.take();

    let mut acp_lock = state.acp.lock().await;
    *acp_lock = Some(connection);
    drop(acp_lock);

    // Spawn inbound handler
    let state_clone = state.clone();
    let client_for_inbound = client.clone();
    tokio::spawn(async move {
        if let Some(mut inbound_rx) = inbound_rx {
            handle_acp_inbound(state_clone, client_for_inbound, &mut inbound_rx).await;
        }
    });

    let protocol_version = params.protocol_version.unwrap_or_else(|| "1.0".to_string());
    let init_params = json!({
        "protocolVersion": protocol_version,
        "clientCapabilities": {
            "fs": { "readTextFile": true, "writeTextFile": true },
        },
        "clientInfo": { "name": "cog.nvim", "version": "0.1.0" }
    });

    let init_resp = client.request("initialize", init_params).await?;

    Ok(json_to_rmpv(&init_resp))
}

async fn handle_disconnect(state: Arc<AppState>) -> Result<Value> {
    let mut lock = state.acp.lock().await;
    if let Some(mut conn) = lock.take() {
        let _ = conn.client.notify("disconnect", JsonValue::Null).await;
        let _ = conn.child.kill().await;
    }
    Ok(Value::from(true))
}

async fn handle_session_new(state: Arc<AppState>, params: Vec<Value>) -> Result<Value> {
    let params: SessionNewParams = as_single_param(params)?;
    let client = get_client(&state).await?;
    let res = client
        .request(
            "session/new",
            json!({
                "cwd": params.cwd,
            }),
        )
        .await?;
    Ok(json_to_rmpv(&res))
}

async fn handle_session_load(state: Arc<AppState>, params: Vec<Value>) -> Result<Value> {
    let params: HashMap<String, String> = as_single_param(params)?;
    let session_id = params
        .get("session_id")
        .ok_or_else(|| anyhow!("session_id required"))?
        .to_string();
    let client = get_client(&state).await?;
    let res = client
        .request(
            "session/load",
            json!({
                "sessionId": session_id,
            }),
        )
        .await?;
    Ok(json_to_rmpv(&res))
}

async fn handle_prompt(state: Arc<AppState>, params: Vec<Value>) -> Result<Value> {
    let params: PromptParams = as_single_param(params)?;
    let client = get_client(&state).await?;
    let prompt = json!([
        {
            "type": "text",
            "text": params.content,
        }
    ]);

    let _ = client
        .request(
            "session/prompt",
            json!({
                "sessionId": params.session_id,
                "prompt": prompt,
            }),
        )
        .await?;

    Ok(Value::from(true))
}

async fn handle_cancel(state: Arc<AppState>, params: Vec<Value>) -> Result<Value> {
    let params: CancelParams = as_single_param(params)?;
    let client = get_client(&state).await?;
    let _ = client
        .request(
            "session/cancel",
            json!({ "sessionId": params.session_id }),
        )
        .await?;
    Ok(Value::from(true))
}

async fn handle_permission_response(state: Arc<AppState>, params: Vec<Value>) -> Result<Value> {
    let params: PermissionResponseParams = as_single_param(params)?;
    let mut pending = state.pending_permission.lock().await;
    if let Some(tx) = pending.remove(&params.request_id) {
        let _ = tx.send(params.option_id);
    }
    Ok(Value::from(true))
}

async fn handle_file_read_response(state: Arc<AppState>, params: Vec<Value>) -> Result<Value> {
    let params: FileReadResponseParams = as_single_param(params)?;
    let mut pending = state.pending_read.lock().await;
    if let Some(tx) = pending.remove(&params.request_id) {
        let _ = tx.send(params.content);
    }
    Ok(Value::from(true))
}

async fn handle_file_write_response(state: Arc<AppState>, params: Vec<Value>) -> Result<Value> {
    let params: FileWriteResponseParams = as_single_param(params)?;
    let mut pending = state.pending_write.lock().await;
    if let Some(tx) = pending.remove(&params.request_id) {
        if params.success {
            let _ = tx.send(Ok(()));
        } else {
            let _ = tx.send(Err(params.message.unwrap_or_else(|| "unknown error".into())));
        }
    }
    Ok(Value::from(true))
}

async fn handle_acp_inbound(
    state: Arc<AppState>,
    client: AcpClient,
    inbound_rx: &mut mpsc::UnboundedReceiver<AcpInbound>,
) {
    while let Some(msg) = inbound_rx.recv().await {
        match msg {
            AcpInbound::Notification { method, params } => {
                if method == "session/update" {
                    state.notify_lua("CogSessionUpdate", params).await;
                } else {
                    state.notify_lua("CogAcpNotification", json!({"method": method, "params": params})).await;
                }
            }
            AcpInbound::Request { id, method, params } => {
                match method.as_str() {
                    "fs/read_text_file" => {
                        let path = params
                            .get("path")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string();
                        let line = params.get("line").cloned().unwrap_or(JsonValue::Null);
                        let limit = params.get("limit").cloned().unwrap_or(JsonValue::Null);

                        let (tx, rx) = oneshot::channel();
                        state.pending_read.lock().await.insert(id, tx);

                        state
                            .notify_lua(
                                "CogFileRead",
                                json!({
                                    "request_id": id,
                                    "path": path,
                                    "line": line,
                                    "limit": limit,
                                }),
                            )
                            .await;

                        let content = rx.await.unwrap_or_default();
                        let _ = client
                            .respond(id, Ok(json!({ "content": content })))
                            .await;
                    }
                    "fs/write_text_file" => {
                        let path = params
                            .get("path")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string();
                        let content = params
                            .get("content")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string();

                        let (tx, rx) = oneshot::channel();
                        state.pending_write.lock().await.insert(id, tx);

                        state
                            .notify_lua(
                                "CogFileWrite",
                                json!({
                                    "request_id": id,
                                    "path": path,
                                    "content": content,
                                }),
                            )
                            .await;

                        let result = rx.await.unwrap_or_else(|_| Err("write failed".into()));
                        let _ = client
                            .respond(
                                id,
                                result.map(|_| json!({})).map_err(|e| anyhow!(e)),
                            )
                            .await;
                    }
                    "session/request_permission" => {
                        let (tx, rx) = oneshot::channel();
                        state.pending_permission.lock().await.insert(id, tx);
                        state
                            .notify_lua(
                                "CogPermissionRequest",
                                json!({
                                    "request_id": id,
                                    "params": params,
                                }),
                            )
                            .await;

                        let option_id = rx.await.unwrap_or_default();
                        let _ = client
                            .respond(
                                id,
                                Ok(json!({
                                    "optionId": option_id,
                                })),
                            )
                            .await;
                    }
                    _ => {
                        let _ = client
                            .respond(id, Err(anyhow!("unsupported method")))
                            .await;
                    }
                }
            }
        }
    }
}

async fn get_client(state: &AppState) -> Result<AcpClient> {
    let lock = state.acp.lock().await;
    let conn = lock.as_ref().ok_or_else(|| anyhow!("not connected"))?;
    Ok(conn.client.clone())
}

fn json_to_rmpv(value: &JsonValue) -> Value {
    match value {
        JsonValue::Null => Value::Nil,
        JsonValue::Bool(b) => Value::from(*b),
        JsonValue::Number(num) => {
            if let Some(i) = num.as_i64() {
                Value::from(i)
            } else if let Some(u) = num.as_u64() {
                Value::from(u)
            } else if let Some(f) = num.as_f64() {
                Value::from(f)
            } else {
                Value::Nil
            }
        }
        JsonValue::String(s) => Value::from(s.clone()),
        JsonValue::Array(arr) => Value::Array(arr.iter().map(json_to_rmpv).collect()),
        JsonValue::Object(map) => Value::Map(
            map.iter()
                .map(|(k, v)| (Value::from(k.clone()), json_to_rmpv(v)))
                .collect(),
        ),
    }
}
