//! E2E test for file editing through cog.nvim chat
//!
//! This test reproduces a bug where file edit operations timeout and
//! nothing appears in neovim. It simulates real user interaction:
//! 1. Opens neovim with cog.nvim loaded
//! 2. Opens the chat UI
//! 3. Sends a file edit request
//! 4. Verifies the edit was applied
//!
//! Run with: cargo test --test edit_file -- --nocapture

use anyhow::{Context, Result};
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use tempfile::TempDir;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let verbose = args.iter().any(|a| a == "--nocapture" || a == "-v");

    println!("╔════════════════════════════════════════════════════╗");
    println!("║  cog.nvim E2E Test: File Edit via Chat             ║");
    println!("╚════════════════════════════════════════════════════╝\n");

    // Create temp directory with test file
    let temp_dir = TempDir::new().context("Failed to create temp directory")?;
    let readme_path = temp_dir.path().join("README.md");

    let initial_content = "# Test README\n\nOriginal content.\n";
    fs::write(&readme_path, initial_content).context("Failed to write initial README")?;

    println!("Test file: {}", readme_path.display());
    println!("Initial content:\n{}", initial_content);

    // Get paths
    let project_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let step_file = project_root.join("step_files/edit_file.yaml");
    let artifacts_dir = project_root.join("test_artifacts");

    fs::create_dir_all(&artifacts_dir).context("Failed to create artifacts directory")?;

    // Build the command
    let mut cmd = Command::new("termwright");
    cmd.arg("run-steps");
    if verbose {
        cmd.arg("--trace");
    }
    cmd.arg(&step_file);
    cmd.current_dir(temp_dir.path());

    // Add cog-agent to PATH
    let cog_agent_path = project_root.parent().unwrap().join("cog-agent/target/debug");
    let mut path = std::env::var("PATH").unwrap_or_default();
    path = format!("{}:{}", cog_agent_path.display(), path);
    cmd.env("PATH", &path);

    println!("\nRunning termwright...");
    println!("Step file: {}", step_file.display());
    println!("Working dir: {}\n", temp_dir.path().display());

    let output = cmd.output().context("Failed to execute termwright")?;

    if verbose {
        if !output.stdout.is_empty() {
            println!("=== STDOUT ===\n{}", String::from_utf8_lossy(&output.stdout));
        }
        if !output.stderr.is_empty() {
            eprintln!("=== STDERR ===\n{}", String::from_utf8_lossy(&output.stderr));
        }
    }

    let termwright_success = output.status.success();
    println!("Termwright exit status: {:?}", output.status);

    // Verify file was modified
    let final_content = fs::read_to_string(&readme_path)
        .context("Failed to read final README content")?;

    println!("\n=== Final README content ===\n{}", final_content);

    let has_marker = final_content.contains("TEST_MARKER_12345");

    // Results
    println!("\n╔════════════════════════════════════════════════════╗");
    println!("║                    TEST RESULTS                    ║");
    println!("╠════════════════════════════════════════════════════╣");

    if termwright_success {
        println!("║  Termwright steps:     ✓ PASS                     ║");
    } else {
        println!("║  Termwright steps:     ✗ FAIL                     ║");
    }

    if has_marker {
        println!("║  File modified:        ✓ PASS                     ║");
    } else {
        println!("║  File modified:        ✗ FAIL                     ║");
    }

    println!("╚════════════════════════════════════════════════════╝");

    // Print artifact locations
    if artifacts_dir.exists() {
        println!("\nArtifacts saved to: {}", artifacts_dir.display());

        // Find most recent run directory
        if let Ok(entries) = fs::read_dir(&artifacts_dir) {
            let mut dirs: Vec<_> = entries
                .filter_map(|e| e.ok())
                .filter(|e| e.file_type().ok().map(|t| t.is_dir()).unwrap_or(false))
                .collect();
            dirs.sort_by_key(|e| e.file_name());

            if let Some(latest) = dirs.last() {
                println!("Latest run: {}", latest.path().display());

                // List screenshots
                if let Ok(files) = fs::read_dir(latest.path()) {
                    println!("\nScreenshots:");
                    for file in files.filter_map(|e| e.ok()) {
                        let name = file.file_name();
                        if name.to_string_lossy().ends_with(".png") {
                            println!("  - {}", name.to_string_lossy());
                        }
                    }
                }
            }
        }
    }

    // Session log hint
    println!("\nSession log: /tmp/cog-e2e-session-updates.log");

    // Final verdict
    if !termwright_success {
        println!("\n[FAIL] Termwright did not complete all steps.");
        println!("This may indicate the test setup has issues.");
        std::process::exit(1);
    }

    if !has_marker {
        println!("\n[FAIL] File was not modified!");
        println!("\nThis reproduces the bug: file edit operations through chat");
        println!("timeout without any visible result in neovim.");
        println!("\nThe message was sent (see screenshots showing 'Thinking...')");
        println!("but codex-acp never returned a response, or the response");
        println!("was not properly handled.");
        std::process::exit(1);
    }

    println!("\n[PASS] All tests passed!");
    Ok(())
}
