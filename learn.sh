#!/bin/bash
# learn.sh — read past git-lrc reviews and extract patterns
# Output: a short summary of what the agent keeps getting wrong

set -euo pipefail

REPO_DIR="${1:-.}"
PATTERNS_FILE="$HOME/.agent-learns/patterns.txt"
mkdir -p "$(dirname "$PATTERNS_FILE")"

cd "$REPO_DIR"

# Collect all review comments from git log trailers
REVIEW_COMMITS=$(git log --oneline --grep="LiveReview Pre-Commit Check: ran" -20 2>/dev/null || true)

if [ -z "$REVIEW_COMMITS" ]; then
  echo "No review history found. Agent has nothing to learn from yet." > "$PATTERNS_FILE"
  cat "$PATTERNS_FILE"
  exit 0
fi

# Extract review JSON from attestations if available
ATTEST_DIR=".git/lrc/attestations"
PATTERNS=""

if [ -d "$ATTEST_DIR" ]; then
  echo "## Past Review Patterns (last 20 reviewed commits)" > "$PATTERNS_FILE"
  echo "" >> "$PATTERNS_FILE"

  # Count review stats
  TOTAL=$(echo "$REVIEW_COMMITS" | wc -l)
  AVERAGE_COV=$(echo "$REVIEW_COMMITS" | grep -oP 'coverage:\K\d+' | awk '{s+=$1} END {print s/NR}' 2>/dev/null || echo "0")
  AVG_ITER=$(echo "$REVIEW_COMMITS" | grep -oP 'iter:\K\d+' | awk '{s+=$1} END {print s/NR}' 2>/dev/null || echo "1")

  echo "- **$TOTAL** commits reviewed this session" >> "$PATTERNS_FILE"
  echo "- Average **${AVERAGE_COV}%** AI coverage" >> "$PATTERNS_FILE"
  echo "- Average **${AVG_ITER}** iterations to get clean" >> "$PATTERNS_FILE"
  echo "" >> "$PATTERNS_FILE"

  # Look for repeated issue patterns across attestation files
  echo "## Things you've been flagged for:" >> "$PATTERNS_FILE"
  echo "" >> "$PATTERNS_FILE"

  # Check for common issue types in the attestation trail
  for attest in "$ATTEST_DIR"/*.json; do
    [ -f "$attest" ] || continue
    # Each attestation tracks coverage/iterations — the actual comments live in the review API
    # We use the metadata to surface patterns
    ACTION=$(jq -r '.action // "unknown"' "$attest" 2>/dev/null || echo "unknown")
    ITER=$(jq -r '.iterations // 1' "$attest" 2>/dev/null || echo "1")
    if [ "$ITER" -gt 2 ]; then
      echo "- Took **$ITER iterations** to pass review (commit $(basename "$attest" .json | head -c 8))" >> "$PATTERNS_FILE"
    fi
  done

  echo "" >> "$PATTERNS_FILE"
  echo "## Guidance for next generation:" >> "$PATTERNS_FILE"
  echo "" >> "$PATTERNS_FILE"

  if [ "$(echo "$AVG_ITER > 1.5" | bc 2>/dev/null || echo 0)" = "1" ]; then
    echo "- You're averaging >1 iteration per commit. Double-check your code before review." >> "$PATTERNS_FILE"
  fi

  if [ "$(echo "$AVERAGE_COV < 70" | bc 2>/dev/null || echo 0)" = "1" ]; then
    echo "- Coverage is low. Make sure you're running review on all changed files." >> "$PATTERNS_FILE"
  fi

  echo "- Review your own diff before committing — look for null checks, error handling, hardcoded values." >> "$PATTERNS_FILE"
else
  echo "## No attestation history yet." > "$PATTERNS_FILE"
  echo "Run a few reviews with git-lrc to build up learning data." >> "$PATTERNS_FILE"
fi

echo "" >> "$PATTERNS_FILE"
echo "---" >> "$PATTERNS_FILE"
echo "Generated $(date)" >> "$PATTERNS_FILE"

cat "$PATTERNS_FILE"
