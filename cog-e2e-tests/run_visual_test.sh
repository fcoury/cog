#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS_DIR="$SCRIPT_DIR/test_artifacts/visual_evaluation"

# Clean up previous artifacts
rm -rf "$ARTIFACTS_DIR"
mkdir -p "$ARTIFACTS_DIR"

echo "=== Running Visual Chat Evaluation Test ==="
echo "This test renders comprehensive mock data to evaluate the chat UI"
echo ""

# Run the visual test
termwright run-steps "$SCRIPT_DIR/step_files/visual_chat_test.yaml"

echo ""
echo "=== Screenshots captured ==="

# Find the latest timestamped directory
LATEST_DIR=$(ls -td "$ARTIFACTS_DIR"/20* 2>/dev/null | head -1)

if [ -n "$LATEST_DIR" ] && ls "$LATEST_DIR"/*.png 1>/dev/null 2>&1; then
    ls -la "$LATEST_DIR"/*.png
    echo ""
    echo "Screenshots saved in: $LATEST_DIR"
else
    echo "No PNG files found in $ARTIFACTS_DIR"
fi

echo ""
echo "=== Visual Evaluation Checklist ==="
echo ""
echo "Review screenshots in: $ARTIFACTS_DIR"
echo ""
echo "Evaluate the following aspects:"
echo ""
echo "Message Rendering:"
echo "  [ ] User messages clearly distinguished (blue border)"
echo "  [ ] Assistant messages readable with good contrast"
echo "  [ ] System messages subtle but visible"
echo "  [ ] Headers with appropriate icons (●, ◆, ○)"
echo ""
echo "Tool Cards:"
echo "  [ ] Clear visual hierarchy (border, icon, status)"
echo "  [ ] Status colors correct (green=success, red=error, yellow=pending)"
echo "  [ ] Diff content readable"
echo "  [ ] Long output truncated gracefully"
echo ""
echo "Layout & Spacing:"
echo "  [ ] Consistent padding between messages"
echo "  [ ] Line wrapping works correctly"
echo "  [ ] No overflow or clipping issues"
echo "  [ ] Scrolling smooth"
echo ""
echo "Thinking Blocks:"
echo "  [ ] <thinking> tags visible"
echo "  [ ] Visually distinct from regular content"
echo ""
echo "Pending State:"
echo "  [ ] 'Thinking...' indicator visible"
echo "  [ ] Status line shows pending state"
echo ""
echo "Code Blocks:"
echo "  [ ] Syntax highlighting applied"
echo "  [ ] Code readable within messages"
echo ""
