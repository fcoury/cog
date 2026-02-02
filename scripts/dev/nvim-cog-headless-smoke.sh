#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export COG_NVIM_TEST_ROOT="$root_dir"

exec nvim --headless -u "$root_dir/scripts/dev/nvim-cog-headless-smoke.vim"
