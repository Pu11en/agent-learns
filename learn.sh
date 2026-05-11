#!/bin/bash
# learn.sh — read past reviews and extract patterns
# Output: a summary of what the agent keeps getting wrong

set -euo pipefail

REPO_DIR="${1:-.}"
ATTEST_DIR="$HOME/.agent-learns/attestations"
PATTERNS_FILE="$HOME/.agent-learns/patterns.txt"
mkdir -p "$(dirname "$PATTERNS_FILE")"

cd "$REPO_DIR"

# Count past reviews
COMMIT_COUNT=0
TOTAL_ITER=0
if [ -d "$ATTEST_DIR" ]; then
  COMMIT_COUNT=$(ls "$ATTEST_DIR"/*.json 2>/dev/null | wc -l)
  for f in "$ATTEST_DIR"/*.json; do
    [ -f "$f" ] || continue
    ITER=$(jq -r '.iterations // 0' "$f" 2>/dev/null || echo "0")
    TOTAL_ITER=$((TOTAL_ITER + ITER))
  done
fi

if [ "$COMMIT_COUNT" -eq 0 ]; then
  echo "No review history yet. Nothing to learn from." > "$PATTERNS_FILE"
  cat "$PATTERNS_FILE"
  exit 0
fi

AVG_ITER=$(echo "scale=1; $TOTAL_ITER / $COMMIT_COUNT" | bc 2>/dev/null || echo "1")

echo "## Review History" > "$PATTERNS_FILE"
echo "" >> "$PATTERNS_FILE"
echo "- **$COMMIT_COUNT** commits reviewed" >> "$PATTERNS_FILE"
echo "- Average **${AVG_ITER}** iterations to pass" >> "$PATTERNS_FILE"
echo "" >> "$PATTERNS_FILE"

# Check for review files that had issues (high iteration counts)
echo "## Things to watch for:" >> "$PATTERNS_FILE"
echo "" >> "$PATTERNS_FILE"

HIGH_ITER_COUNT=0
for f in "$ATTEST_DIR"/*.json; do
  [ -f "$f" ] || continue
  ITER=$(jq -r '.iterations // 1' "$f" 2>/dev/null || echo "1")
  if [ "$ITER" -gt 2 ]; then
    HIGH_ITER_COUNT=$((HIGH_ITER_COUNT + 1))
    TREE=$(basename "$f" .json | head -c 8)
    echo "- Took **$ITER iterations** — commit $TREE needed multiple fixes" >> "$PATTERNS_FILE"
  fi
done

echo "" >> "$PATTERNS_FILE"
echo "## Guidance:" >> "$PATTERNS_FILE"
echo "" >> "$PATTERNS_FILE"

if [ "$HIGH_ITER_COUNT" -gt 2 ]; then
  echo "- You've needed multiple fix rounds on $HIGH_ITER_COUNT commits recently. Slow down and double-check before submitting." >> "$PATTERNS_FILE"
fi

if [ "$(echo "$AVG_ITER > 1.5" | bc 2>/dev/null || echo 0)" = "1" ]; then
  echo "- Averaging >1 iteration per commit. Review your own diff before the first review." >> "$PATTERNS_FILE"
fi

echo "- Common issues to check: null references, missing error handling, hardcoded values, missing input validation." >> "$PATTERNS_FILE"
echo "- If you're touching async code, verify every promise/callback has error handling." >> "$PATTERNS_FILE"
echo "- If you're touching UI components, verify accessibility (aria labels, keyboard nav)." >> "$PATTERNS_FILE"

echo "" >> "$PATTERNS_FILE"
echo "---" >> "$PATTERNS_FILE"
echo "Generated $(date)" >> "$PATTERNS_FILE"

cat "$PATTERNS_FILE"
