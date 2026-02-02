#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

echo "==> Git status"
git status -sb

if command -v cargo >/dev/null 2>&1; then
  if command -v rustfmt >/dev/null 2>&1; then
    echo "==> Rust format (cog-agent)"
    (cd "$root_dir/cog-agent" && cargo fmt)
  else
    echo "rustfmt not found; skipping format"
  fi

  echo "==> Rust tests (cog-agent)"
  (cd "$root_dir/cog-agent" && cargo test)
else
  echo "cargo not found; skipping Rust checks"
fi

echo "==> Done"

if command -v nvim >/dev/null 2>&1; then
  echo "==> Headless Neovim smoke (cog.nvim)"
  "$root_dir/scripts/dev/nvim-cog-headless-smoke.sh"
  echo "==> Headless Neovim ACP stub (cog.nvim)"
  "$root_dir/scripts/dev/nvim-cog-acp-stub.sh"
  echo "==> Snapshot compare (ACP stub)"
  "$root_dir/scripts/dev/compare-snapshots.sh" \
    "$root_dir/scripts/dev/out/chat-acp-stub.txt" \
    "$root_dir/scripts/dev/snapshots/chat-acp-stub.txt"
  if [[ "${COG_E2E:-}" == "1" ]]; then
    echo "==> Headless Neovim E2E (cog.nvim)"
    "$root_dir/scripts/dev/nvim-cog-e2e.sh"
  else
    echo "COG_E2E not set to 1; skipping e2e"
  fi
else
  echo "nvim not found; skipping headless smoke test"
fi
