use serde_json::{json, Value};
use std::env;
use std::io::{self, BufRead, Write};
use std::time::{Duration, Instant};

#[derive(Debug, Clone)]
struct StubConfig {
    session_id: String,
    tool_call_id: String,
    target_path: Option<String>,
    write_content: String,
    prompt_delay_ms: u64,
}

impl StubConfig {
    fn from_env() -> Self {
        let session_id = env::var("ACP_STUB_SESSION_ID").unwrap_or_else(|_| "stub-session".into());
        let tool_call_id = env::var("ACP_STUB_TOOL_CALL_ID").unwrap_or_else(|_| "tool-1".into());
        let target_path = env::var("ACP_STUB_TARGET_PATH")
            .ok()
            .filter(|s| !s.is_empty());
        let write_content =
            env::var("ACP_STUB_WRITE_CONTENT").unwrap_or_else(|_| "Hello from ACP stub\n".into());
        let prompt_delay_ms = env::var("ACP_STUB_PROMPT_DELAY_MS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(50);

        Self {
            session_id,
            tool_call_id,
            target_path,
            write_content,
            prompt_delay_ms,
        }
    }
}

#[derive(Debug)]
struct StubState {
    next_id: u64,
    pending_write_id: Option<u64>,
    waiting_for_write_response_since: Option<Instant>,
}

impl StubState {
    fn new() -> Self {
        Self {
            next_id: 1000,
            pending_write_id: None,
            waiting_for_write_response_since: None,
        }
    }

    fn next_request_id(&mut self) -> u64 {
        let id = self.next_id;
        self.next_id += 1;
        id
    }
}

fn main() -> io::Result<()> {
    let config = StubConfig::from_env();
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let mut state = StubState::new();

    for line in stdin.lock().lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }

        let value: Value = match serde_json::from_str(&line) {
            Ok(v) => v,
            Err(err) => {
                eprintln!("acp-stub: invalid json: {err}");
                continue;
            }
        };

        // Handle responses to our requests first
        if let Some(id) = value.get("id").and_then(|v| v.as_u64()) {
            if value.get("method").is_none() && state.pending_write_id == Some(id) {
                state.pending_write_id = None;
                state.waiting_for_write_response_since = None;
                send_tool_call_update(&mut stdout, &config, "completed", None)?;
                send_agent_message(&mut stdout, "Write completed via stub.")?;
                continue;
            }
        }

        // Only handle requests with method
        let method = value.get("method").and_then(|v| v.as_str()).unwrap_or("");
        let id = value.get("id").and_then(|v| v.as_u64());

        match method {
            "initialize" => {
                let result = json!({
                    "serverInfo": { "name": "acp-stub", "version": "0.1.0" },
                    "capabilities": {
                        "fs": { "readTextFile": true, "writeTextFile": true },
                        "session": {}
                    }
                });
                respond(&mut stdout, id, result)?;
            }
            "session/new" | "session/load" => {
                let result = json!({ "sessionId": config.session_id });
                respond(&mut stdout, id, result)?;
            }
            "session/set_mode" | "session/set_model" | "session/cancel" => {
                respond(&mut stdout, id, json!({}))?;
            }
            "session/prompt" => {
                respond(&mut stdout, id, json!({ "stopReason": "completed" }))?;

                if config.prompt_delay_ms > 0 {
                    std::thread::sleep(Duration::from_millis(config.prompt_delay_ms));
                }

                send_agent_message_chunk(&mut stdout, "Stub: ")?;
                send_agent_message(&mut stdout, "streaming response.")?;

                send_tool_call_update(&mut stdout, &config, "in_progress", None)?;

                if let Some(path) = &config.target_path {
                    let request_id = state.next_request_id();
                    state.pending_write_id = Some(request_id);
                    state.waiting_for_write_response_since = Some(Instant::now());
                    send_write_request(&mut stdout, request_id, path, &config.write_content)?;
                } else {
                    send_tool_call_update(&mut stdout, &config, "completed", None)?;
                }
            }
            _ => {
                if id.is_some() {
                    respond_error(&mut stdout, id, -32601, "method not found")?;
                }
            }
        }

        // Guard: if waiting too long, emit a failure update and clear
        if let Some(since) = state.waiting_for_write_response_since {
            if since.elapsed() > Duration::from_secs(5) {
                state.pending_write_id = None;
                state.waiting_for_write_response_since = None;
                send_tool_call_update(&mut stdout, &config, "failed", Some("write timeout"))?;
            }
        }
    }

    Ok(())
}

fn respond(out: &mut dyn Write, id: Option<u64>, result: Value) -> io::Result<()> {
    if let Some(id) = id {
        let msg = json!({
            "jsonrpc": "2.0",
            "id": id,
            "result": result,
        });
        write_line(out, &msg)?;
    }
    Ok(())
}

fn respond_error(out: &mut dyn Write, id: Option<u64>, code: i64, message: &str) -> io::Result<()> {
    if let Some(id) = id {
        let msg = json!({
            "jsonrpc": "2.0",
            "id": id,
            "error": { "code": code, "message": message },
        });
        write_line(out, &msg)?;
    }
    Ok(())
}

fn send_agent_message_chunk(out: &mut dyn Write, text: &str) -> io::Result<()> {
    let update = json!({
        "type": "agent_message_chunk",
        "text": text,
    });
    send_session_update(out, update)
}

fn send_agent_message(out: &mut dyn Write, text: &str) -> io::Result<()> {
    let update = json!({
        "type": "agent_message",
        "text": text,
    });
    send_session_update(out, update)
}

fn send_tool_call_update(
    out: &mut dyn Write,
    config: &StubConfig,
    status: &str,
    error: Option<&str>,
) -> io::Result<()> {
    let mut tool_call = json!({
        "toolCallId": config.tool_call_id,
        "title": "Edit file",
        "kind": "edit",
        "status": status,
    });

    if let Some(path) = &config.target_path {
        tool_call["locations"] = json!([{ "path": path }]);
    }

    if let Some(error) = error {
        tool_call["error"] = json!(error);
    }

    let update = json!({
        "type": "tool_call",
        "toolCall": tool_call,
        "status": status,
    });
    send_session_update(out, update)
}

fn send_write_request(out: &mut dyn Write, id: u64, path: &str, content: &str) -> io::Result<()> {
    let msg = json!({
        "jsonrpc": "2.0",
        "id": id,
        "method": "fs/write_text_file",
        "params": {
            "path": path,
            "content": content,
        }
    });
    write_line(out, &msg)
}

fn send_session_update(out: &mut dyn Write, update: Value) -> io::Result<()> {
    let msg = json!({
        "jsonrpc": "2.0",
        "method": "session/update",
        "params": update,
    });
    write_line(out, &msg)
}

fn write_line(out: &mut dyn Write, msg: &Value) -> io::Result<()> {
    let mut buf = serde_json::to_vec(msg).unwrap_or_default();
    buf.push(b'\n');
    out.write_all(&buf)?;
    out.flush()?;
    Ok(())
}
