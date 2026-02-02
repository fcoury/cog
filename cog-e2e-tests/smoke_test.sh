#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS_DIR="$SCRIPT_DIR/test_artifacts"

# Clean artifacts
rm -rf "$ARTIFACTS_DIR"
mkdir -p "$ARTIFACTS_DIR"

# Create temp test dir
TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

echo "# Test README" > "$TEMP_DIR/README.md"
cd "$TEMP_DIR"

echo "Running smoke test from: $TEMP_DIR"
echo "Step file: $SCRIPT_DIR/step_files/smoke_test.yaml"
echo ""

termwright run-steps --trace "$SCRIPT_DIR/step_files/smoke_test.yaml"

echo ""
echo "Done. Artifacts in: $ARTIFACTS_DIR"
ls -la "$ARTIFACTS_DIR" 2>/dev/null || true
