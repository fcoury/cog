#!/bin/bash
# Test chat buffer persistence across nvim sessions
# Runs two nvim sessions sequentially to reproduce the bug

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS_DIR="$SCRIPT_DIR/test_artifacts/chat_persistence"

rm -rf "$ARTIFACTS_DIR"
mkdir -p "$ARTIFACTS_DIR"

# Create temp test dir
TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

echo "# Test README" > "$TEMP_DIR/README.md"
cd "$TEMP_DIR"

echo "=== Session 1: Open chat, close nvim ==="
termwright run-steps "$SCRIPT_DIR/step_files/chat_session1.yaml" || true

echo ""
echo "=== Session 2: Reopen nvim, try to toggle chat ==="
if termwright run-steps "$SCRIPT_DIR/step_files/chat_session2.yaml"; then
    echo "[PASS] Chat opened successfully in second session"
    exit 0
else
    echo "[FAIL] Chat failed to open - buffer persistence bug confirmed"
    exit 1
fi
