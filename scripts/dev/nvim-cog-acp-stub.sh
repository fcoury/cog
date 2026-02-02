#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export COG_NVIM_TEST_ROOT="$root_dir"

tmp_dir="$(mktemp -d /tmp/cog-acp-stub-XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

target_file="$tmp_dir/target.txt"
echo "Original content" > "$target_file"

stub_content=$'Stub wrote this line\nAnd another line'

export COG_ACP_STUB_WORKDIR="$tmp_dir"
export COG_ACP_STUB_TARGET="$target_file"
export COG_ACP_STUB_CONTENT="$stub_content"

if command -v cargo >/dev/null 2>&1; then
  (cd "$root_dir/cog-agent" && cargo build)
else
  echo "cargo not found; cannot build cog-agent/acp_stub"
  exit 1
fi

export COG_NVIM_AGENT_BIN="${COG_NVIM_AGENT_BIN:-$root_dir/cog-agent/target/debug/cog-agent}"
export COG_ACP_STUB_BIN="${COG_ACP_STUB_BIN:-$root_dir/cog-agent/target/debug/acp_stub}"

exec nvim --headless -u "$root_dir/scripts/dev/nvim-cog-acp-stub.vim"
