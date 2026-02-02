#!/bin/bash
set -euo pipefail

# E2E test runner for cog.nvim + cog-agent
# Uses termwright to automate neovim interaction
#
# This test reproduces a bug where file edit operations through chat
# timeout and nothing appears in neovim.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="$SCRIPT_DIR/test_artifacts"
STEP_FILE="$SCRIPT_DIR/step_files/edit_file.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "╔════════════════════════════════════════════════════╗"
echo "║  cog.nvim E2E Test: File Edit via Chat             ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
echo -e "${CYAN}Checking prerequisites...${NC}"

if ! command -v termwright &> /dev/null; then
    echo -e "${RED}ERROR: termwright not found. Install with: cargo install termwright${NC}"
    exit 1
fi

if ! command -v nvim &> /dev/null; then
    echo -e "${RED}ERROR: nvim not found${NC}"
    exit 1
fi

if ! command -v codex-acp &> /dev/null; then
    echo -e "${RED}ERROR: codex-acp not found${NC}"
    exit 1
fi

COG_AGENT="$PROJECT_ROOT/cog-agent/target/debug/cog-agent"
if [ ! -f "$COG_AGENT" ]; then
    echo -e "${YELLOW}Building cog-agent...${NC}"
    (cd "$PROJECT_ROOT/cog-agent" && cargo build)
fi

echo -e "${GREEN}✓ All prerequisites OK${NC}"
echo ""

# Create temp directory with test file
TEMP_DIR=$(mktemp -d)
README_PATH="$TEMP_DIR/README.md"
trap "rm -rf '$TEMP_DIR'" EXIT

cat > "$README_PATH" << 'EOF'
# Test README

Original content.
EOF

echo "Test file: $README_PATH"
echo "Initial content:"
echo "  # Test README"
echo "  Original content."
echo ""

# Clean previous artifacts
rm -rf "$ARTIFACTS_DIR"
mkdir -p "$ARTIFACTS_DIR"

# Add cog-agent to PATH
export PATH="$PROJECT_ROOT/cog-agent/target/debug:$PATH"

echo -e "${CYAN}Running termwright...${NC}"
echo "Step file: $STEP_FILE"
echo "Working directory: $TEMP_DIR"
echo ""

cd "$TEMP_DIR"

# Run with trace for debugging
if termwright run-steps --trace "$STEP_FILE"; then
    TERMWRIGHT_SUCCESS=true
else
    TERMWRIGHT_SUCCESS=false
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "                    FINAL FILE CONTENT"
echo "═══════════════════════════════════════════════════════"
cat "$README_PATH" || true
echo ""
echo "═══════════════════════════════════════════════════════"

# Check for test marker
if grep -q "TEST_MARKER_12345" "$README_PATH" 2>/dev/null; then
    HAS_MARKER=true
else
    HAS_MARKER=false
fi

# Print results
echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║                    TEST RESULTS                    ║"
echo "╠════════════════════════════════════════════════════╣"
if [ "$TERMWRIGHT_SUCCESS" = true ]; then
    echo -e "║  Termwright steps:     ${GREEN}✓ PASS${NC}                     ║"
else
    echo -e "║  Termwright steps:     ${RED}✗ FAIL${NC}                     ║"
fi
if [ "$HAS_MARKER" = true ]; then
    echo -e "║  File modified:        ${GREEN}✓ PASS${NC}                     ║"
else
    echo -e "║  File modified:        ${RED}✗ FAIL${NC}                     ║"
fi
echo "╚════════════════════════════════════════════════════╝"

# Print artifact locations
echo ""
echo "Artifacts saved to: $ARTIFACTS_DIR"
if [ -d "$ARTIFACTS_DIR" ]; then
    LATEST=$(ls -1d "$ARTIFACTS_DIR"/*/ 2>/dev/null | tail -1)
    if [ -n "$LATEST" ]; then
        echo "Latest run: $LATEST"
        echo ""
        echo "Screenshots:"
        ls "$LATEST"/*.png 2>/dev/null | while read f; do
            echo "  - $(basename "$f")"
        done
    fi
fi

# Session log hint
echo ""
echo "Session log: /tmp/cog-e2e-session-updates.log"

# Final verdict
echo ""
if [ "$TERMWRIGHT_SUCCESS" = true ] && [ "$HAS_MARKER" = true ]; then
    echo -e "${GREEN}[PASS] All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}[FAIL] Test failed${NC}"
    if [ "$TERMWRIGHT_SUCCESS" = false ]; then
        echo "  - Termwright did not complete all steps"
    fi
    if [ "$HAS_MARKER" = false ]; then
        echo ""
        echo "This reproduces the bug: file edit operations through chat"
        echo "timeout without any visible result in neovim."
        echo ""
        echo "The message was sent (see screenshots showing 'Thinking...')"
        echo "but codex-acp never returned a response, or the response"
        echo "was not properly handled."
    fi
    exit 1
fi
