# Dev scripts

## verify.sh
Runs the local verification routine:
- `cargo fmt`
- `cargo test` (cog-agent)
- Neovim headless smoke
- Neovim ACP stub E2E + snapshot compare

Usage:
```
scripts/dev/verify.sh
```

## nvim-cog-smoke.sh
Launches Neovim with `cog.nvim` (and `amp.nvim` in runtimepath) for a manual user-perspective smoke test.

Usage:
```
scripts/dev/nvim-cog-smoke.sh
```

In Neovim:
1. Run `:CogSmoke` to connect.
2. Send a prompt that edits a file (e.g. "Add a comment to README.md").
3. Verify tool card diff updates while edits apply.
4. Confirm buffer and disk changes.

## nvim-cog-headless-smoke.sh
Headless smoke test that simulates streaming, tool call rendering, and diff updates.
Writes chat buffer output to `scripts/dev/out/chat.txt` for inspection.

Usage:
```
scripts/dev/nvim-cog-headless-smoke.sh
```

## nvim-cog-acp-stub.sh
Headless E2E test that uses a local ACP stub server (no network).
Exercises streaming, tool call rendering, diff generation, and file writes via the real `cog-agent`.
Writes chat buffer output to `scripts/dev/out/chat-acp-stub.txt`.

Usage:
```
scripts/dev/nvim-cog-acp-stub.sh
```

Snapshot:
- Baseline: `scripts/dev/snapshots/chat-acp-stub.txt`
- Update baseline: `COG_UPDATE_SNAPSHOTS=1 scripts/dev/nvim-cog-acp-stub.sh`

## nvim-cog-e2e.sh
Headless end-to-end test that connects to codex-acp and runs a real prompt.
Requires environment variables:
- `COG_E2E_PROMPT` (e.g. "Add a comment to README.md")

Auth:
- Uses Codex CLI stored auth if available.
- Optional: `OPENAI_API_KEY` or `CODEX_API_KEY` if you want to override.

Workspace:
- Uses a temp workdir by default: `/tmp/cog-e2e-XXXXXX`.
- Override with `COG_E2E_WORKDIR`.

Target file:
- `COG_E2E_TARGET` (relative path, default: `README.md`).
- A file is created and a default prompt is generated if `COG_E2E_PROMPT` is not set.

Writes output to `scripts/dev/out/chat-e2e.txt`.

Usage:
```
COG_E2E_PROMPT="Add a comment to README.md" OPENAI_API_KEY=... scripts/dev/nvim-cog-e2e.sh
COG_E2E_TARGET="notes.md" scripts/dev/nvim-cog-e2e.sh
COG_E2E_WORKDIR="/tmp/cog-e2e-custom" COG_E2E_TARGET="notes.md" scripts/dev/nvim-cog-e2e.sh
```
