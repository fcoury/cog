# cog-e2e-tests

End-to-end tests for cog.nvim + cog-agent using [Termwright](https://crates.io/crates/termwright) TUI automation.

## Purpose

These tests reproduce a bug where file edit operations through the cog.nvim chat timeout and nothing appears in neovim. The test:

1. Starts neovim with cog.nvim loaded
2. Opens the chat UI
3. Sends a file edit request
4. Verifies the edit was applied to the file

## Prerequisites

- `termwright` - Install with `cargo install termwright`
- `nvim` - Neovim
- `codex-acp` - The ACP backend
- `cog-agent` - Built from `../cog-agent`

## Running Tests

### Quick (shell script)

```bash
./run_test.sh
```

### Rust test runner

```bash
cargo test --test edit_file -- --nocapture
```

## Test Artifacts

After a test run, artifacts are saved to `test_artifacts/<timestamp>/`:

- `*.png` - Screenshots at key steps
- `step-*-screen.txt` - Terminal text content at each step
- `trace.json` - Step timing and error information

## Expected Behavior

### With the bug (current state)

```
╔════════════════════════════════════════════════════╗
║                    TEST RESULTS                    ║
╠════════════════════════════════════════════════════╣
║  Termwright steps:     ✓ PASS                     ║
║  File modified:        ✗ FAIL                     ║
╚════════════════════════════════════════════════════╝

[FAIL] File was not modified!

This reproduces the bug: file edit operations through chat
timeout without any visible result in neovim.
```

Screenshots will show:
- Chat opens successfully
- Message is sent
- "Thinking..." appears
- Response never arrives

### After fix

```
╔════════════════════════════════════════════════════╗
║                    TEST RESULTS                    ║
╠════════════════════════════════════════════════════╣
║  Termwright steps:     ✓ PASS                     ║
║  File modified:        ✓ PASS                     ║
╚════════════════════════════════════════════════════╝

[PASS] All tests passed!
```

## Files

| File | Purpose |
|------|---------|
| `run_test.sh` | Shell script test runner |
| `step_files/edit_file.yaml` | Main test: file edit via chat |
| `step_files/smoke_test.yaml` | Quick test: verify chat opens |
| `nvim_test_config/init.lua` | Neovim config for testing |
| `tests/edit_file_test.rs` | Rust test runner |

## Debug Tips

1. Check screenshots in `test_artifacts/` to see the UI state
2. Review `trace.json` for step timing (0ms = instant match or skip)
3. Check `/tmp/cog-e2e-session-updates.log` for cog.nvim session logs
4. Run smoke test first: `./smoke_test.sh`
