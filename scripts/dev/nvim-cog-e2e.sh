#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export COG_NVIM_TEST_ROOT="$root_dir"
export COG_NVIM_AGENT_BIN="$root_dir/cog-agent/target/debug/cog-agent"

workdir="${COG_E2E_WORKDIR:-}"
if [[ -z "$workdir" ]]; then
  workdir="$(mktemp -d /tmp/cog-e2e-XXXXXX)"
  export COG_E2E_WORKDIR="$workdir"
fi

mkdir -p "$workdir"

target="${COG_E2E_TARGET:-README.md}"
target_path="$workdir/$target"
mkdir -p "$(dirname "$target_path")"
marker="${COG_E2E_MARKER:-COG_E2E_MARKER}"
export COG_E2E_MARKER="$marker"
printf "E2E base\n" > "$target_path"

if [[ ! -d "$workdir/.git" ]]; then
  git -C "$workdir" init >/dev/null 2>&1 || true
fi

if [[ -z "${COG_E2E_PROMPT:-}" ]]; then
  export COG_E2E_PROMPT="Replace the entire contents of ${target} with exactly:\n${marker}\n"
fi

if [[ ! -x "$COG_NVIM_AGENT_BIN" ]]; then
  (cd "$root_dir/cog-agent" && cargo build)
fi

exec nvim --headless -u "$root_dir/scripts/dev/nvim-cog-e2e.vim"
