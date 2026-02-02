use cog_agent::acp::{AcpClient, AcpInbound};
use serde_json::json;
use std::collections::HashMap;
use std::path::PathBuf;
use std::time::Duration;
use tokio::time::timeout;

fn stub_bin() -> String {
    if let Ok(bin) = std::env::var("CARGO_BIN_EXE_acp_stub") {
        return bin;
    }

    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR not set");
    let bin_path = std::path::Path::new(&manifest_dir)
        .join("target")
        .join("debug")
        .join("acp_stub");

    if bin_path.exists() {
        return bin_path.to_string_lossy().to_string();
    }

    let status = std::process::Command::new("cargo")
        .args(["build", "--bin", "acp_stub"])
        .current_dir(&manifest_dir)
        .status()
        .expect("failed to run cargo build --bin acp_stub");
    assert!(status.success(), "cargo build --bin acp_stub failed");

    bin_path.to_string_lossy().to_string()
}

fn temp_target_path() -> PathBuf {
    let mut path = std::env::temp_dir();
    let unique = format!(
        "cog-agent-acp-stub-{}-{}.txt",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis()
    );
    path.push(unique);
    path
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn acp_stub_roundtrip() {
    let target_path = temp_target_path();
    let mut env = HashMap::new();
    env.insert(
        "ACP_STUB_TARGET_PATH".to_string(),
        target_path.to_string_lossy().to_string(),
    );
    env.insert(
        "ACP_STUB_WRITE_CONTENT".to_string(),
        "stub write content\n".to_string(),
    );

    let mut conn = AcpClient::spawn(vec![stub_bin()], env, None)
        .await
        .expect("spawn acp_stub");
    let client = conn.client.clone();
    let mut inbound = conn.inbound_rx.take().expect("missing inbound_rx");

    let init = client
        .request("initialize", json!({}))
        .await
        .expect("initialize");
    assert!(init.get("serverInfo").is_some());

    let session = client
        .request("session/new", json!({ "cwd": null }))
        .await
        .expect("session/new");
    assert_eq!(
        session.get("sessionId").and_then(|v| v.as_str()),
        Some("stub-session")
    );

    client
        .request(
            "session/prompt",
            json!({ "sessionId": "stub-session", "prompt": [] }),
        )
        .await
        .expect("session/prompt");

    let mut saw_update = false;
    let mut saw_write_request = false;

    for _ in 0..20 {
        let msg = timeout(Duration::from_secs(1), inbound.recv())
            .await
            .expect("timeout waiting for inbound")
            .expect("inbound closed");

        match msg {
            AcpInbound::Notification { method, params } => {
                if method == "session/update" {
                    let update_type = params.get("type").and_then(|v| v.as_str()).unwrap_or("");
                    if update_type == "agent_message" || update_type == "agent_message_chunk" {
                        saw_update = true;
                    }
                }
            }
            AcpInbound::Request {
                id,
                method,
                params: _,
            } => {
                if method == "fs/write_text_file" {
                    saw_write_request = true;
                    client
                        .respond(id, Ok(json!({})))
                        .await
                        .expect("respond to write");
                }
            }
        }

        if saw_update && saw_write_request {
            break;
        }
    }

    assert!(saw_update, "expected agent message update");
    assert!(saw_write_request, "expected write_text_file request");
}
