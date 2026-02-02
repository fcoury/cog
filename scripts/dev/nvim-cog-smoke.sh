#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export COG_NVIM_TEST_ROOT="$root_dir"

cat <<'EOF'
Manual smoke test steps (automated launch):
1) Neovim starts with cog.nvim in runtimepath.
2) Run :CogConnect (or trigger a prompt).
3) Send a prompt that edits a file (e.g. "Add a comment to README.md").
4) Observe tool card diff updates while the edit applies.
5) Verify file content changed in buffer and on disk.
EOF

exec nvim -u "$root_dir/scripts/dev/nvim-cog-smoke.vim"
