use anyhow::{anyhow, Result};
use rmpv::Value;
use std::collections::HashMap;
use std::io::{self, BufReader, BufWriter, Write};
use std::sync::{Arc, Mutex};
use tokio::sync::{mpsc, oneshot};

#[derive(Debug)]
pub enum RpcMessage {
    Request {
        msgid: u64,
        method: String,
        params: Vec<Value>,
    },
    Response {
        msgid: u64,
        error: Option<Value>,
        result: Option<Value>,
    },
    Notification {
        method: String,
        params: Vec<Value>,
    },
}

pub fn parse_message(val: Value) -> Result<RpcMessage> {
    let arr = match val {
        Value::Array(arr) => arr,
        _ => return Err(anyhow!("msgpack-rpc message is not array")),
    };

    let msg_type = arr
        .get(0)
        .and_then(|v| v.as_i64())
        .ok_or_else(|| anyhow!("missing msg type"))?;

    match msg_type {
        0 => {
            let msgid = arr
                .get(1)
                .and_then(|v| v.as_u64())
                .ok_or_else(|| anyhow!("missing msgid"))?;
            let method = arr
                .get(2)
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("missing method"))?
                .to_string();
            let params = match arr.get(3) {
                Some(Value::Array(p)) => p.clone(),
                Some(_) => return Err(anyhow!("params must be array")),
                None => Vec::new(),
            };
            Ok(RpcMessage::Request {
                msgid,
                method,
                params,
            })
        }
        1 => {
            let msgid = arr
                .get(1)
                .and_then(|v| v.as_u64())
                .ok_or_else(|| anyhow!("missing msgid"))?;
            let error = arr.get(2).cloned();
            let result = arr.get(3).cloned();
            Ok(RpcMessage::Response {
                msgid,
                error,
                result,
            })
        }
        2 => {
            let method = arr
                .get(1)
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("missing method"))?
                .to_string();
            let params = match arr.get(2) {
                Some(Value::Array(p)) => p.clone(),
                Some(_) => return Err(anyhow!("params must be array")),
                None => Vec::new(),
            };
            Ok(RpcMessage::Notification { method, params })
        }
        _ => Err(anyhow!("unknown msg type")),
    }
}

pub fn encode_request(msgid: u64, method: &str, params: Vec<Value>) -> Value {
    Value::Array(vec![
        Value::from(0),
        Value::from(msgid as i64),
        Value::from(method.to_string()),
        Value::Array(params),
    ])
}

pub fn encode_response(msgid: u64, error: Option<Value>, result: Option<Value>) -> Value {
    Value::Array(vec![
        Value::from(1),
        Value::from(msgid as i64),
        error.unwrap_or(Value::Nil),
        result.unwrap_or(Value::Nil),
    ])
}

pub fn encode_notification(method: &str, params: Vec<Value>) -> Value {
    Value::Array(vec![
        Value::from(2),
        Value::from(method.to_string()),
        Value::Array(params),
    ])
}

pub fn start_reader_thread(tx: mpsc::UnboundedSender<Value>) {
    std::thread::spawn(move || {
        let stdin = io::stdin();
        let mut reader = BufReader::new(stdin.lock());
        loop {
            match rmpv::decode::read_value(&mut reader) {
                Ok(val) => {
                    let _ = tx.send(val);
                }
                Err(err) => {
                    if err.kind() == io::ErrorKind::UnexpectedEof {
                        break;
                    }
                    eprintln!("rpc read error: {err}");
                    break;
                }
            }
        }
    });
}

pub fn start_writer_thread(mut rx: mpsc::UnboundedReceiver<Value>) {
    std::thread::spawn(move || {
        let stdout = io::stdout();
        let mut writer = BufWriter::new(stdout.lock());
        while let Some(val) = rx.blocking_recv() {
            if let Err(err) = rmpv::encode::write_value(&mut writer, &val) {
                eprintln!("rpc write error: {err}");
                break;
            }
            let _ = writer.flush();
        }
    });
}

#[derive(Clone)]
pub struct RpcClient {
    tx: mpsc::UnboundedSender<Value>,
    pending: Arc<Mutex<HashMap<u64, oneshot::Sender<Result<Value>>>>>,
    next_id: Arc<Mutex<u64>>,
}

impl RpcClient {
    pub fn new(tx: mpsc::UnboundedSender<Value>) -> Self {
        Self {
            tx,
            pending: Arc::new(Mutex::new(HashMap::new())),
            next_id: Arc::new(Mutex::new(1)),
        }
    }

    pub fn handle_response(&self, msgid: u64, error: Option<Value>, result: Option<Value>) {
        let sender = self.pending.lock().unwrap().remove(&msgid);
        if let Some(sender) = sender {
            let _ = sender.send(match error {
                Some(err) if !err.is_nil() => Err(anyhow!("rpc error: {err:?}")),
                _ => Ok(result.unwrap_or(Value::Nil)),
            });
        }
    }

    pub fn request(&self, method: &str, params: Vec<Value>) -> oneshot::Receiver<Result<Value>> {
        let mut next_id = self.next_id.lock().unwrap();
        let msgid = *next_id;
        *next_id += 1;
        let (tx, rx) = oneshot::channel();
        self.pending.lock().unwrap().insert(msgid, tx);
        let msg = encode_request(msgid, method, params);
        let _ = self.tx.send(msg);
        rx
    }

    pub fn notify(&self, method: &str, params: Vec<Value>) {
        let msg = encode_notification(method, params);
        let _ = self.tx.send(msg);
    }
}

pub fn as_single_param<T>(params: Vec<Value>) -> Result<T>
where
    T: serde::de::DeserializeOwned,
{
    if params.len() != 1 {
        return Err(anyhow!("expected single param, got {}", params.len()));
    }
    let value = params.into_iter().next().unwrap();
    let parsed = rmpv::ext::from_value(value)?;
    Ok(parsed)
}
