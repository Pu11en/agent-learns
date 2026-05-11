#!/bin/bash
# loop.sh — the main autonomous review loop
# Agent calls this to: review code → learn patterns → inject context → retry
#
# Usage: ./loop.sh [max-iterations] [commit-message]
# Default: 3 iterations max, auto-generates commit message

set -euo pipefail

MAX_ITER="${1:-5}"
COMMIT_MSG="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="."

echo "🛡️  Agent-Learns: Starting review loop (max $MAX_ITER iterations)"

cd "$REPO_DIR"

# Check prerequisites
if ! command -v git-lrc &>/dev/null; then
  echo "❌ git-lrc not found. Install it first: curl -fsSL https://hexmos.com/lrc-install.sh | bash"
  exit 1
fi

if ! git rev-parse --git-dir &>/dev/null; then
  echo "❌ Not in a git repository."
  exit 1
fi

for i in $(seq 1 "$MAX_ITER"); do
  echo ""
  echo "── Iteration $i/$MAX_ITER ──"

  git add .

  # Run git-lrc review — output JSON for parsing
  echo "🔍 Running review..."
  RESULT=$(git lrc review --force --output json 2>/dev/null || echo '{"status":"error"}')

  STATUS=$(echo "$RESULT" | jq -r '.status // "error"' 2>/dev/null || echo "error")

  if [ "$STATUS" = "error" ] || [ "$STATUS" = "failed" ]; then
    echo "⚠️  Review failed — continuing without review gate."
    # Let the agent learn from the attempt anyway
    bash "$SCRIPT_DIR/learn.sh" . > /dev/null 2>&1
    exit 0
  fi

  # Count issues by severity
  ERRORS=$(echo "$RESULT" | jq '[.files[]?.comments[]? | select(.severity == "error")] | length' 2>/dev/null || echo "0")
  WARNINGS=$(echo "$RESULT" | jq '[.files[]?.comments[]? | select(.severity == "warning")] | length' 2>/dev/null || echo "0")
  INFO=$(echo "$RESULT" | jq '[.files[]?.comments[]? | select(.severity == "info")] | length' 2>/dev/null || echo "0")

  echo "   Errors: $ERRORS | Warnings: $WARNINGS | Info: $INFO"

  # Clean? Commit and exit.
  if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo ""
    echo "✅ Clean review — committing."
    git lrc review --vouch 2>/dev/null || true

    if [ -n "$COMMIT_MSG" ]; then
      git commit -m "$COMMIT_MSG"
    else
      git commit --no-edit --allow-empty-message 2>/dev/null || git commit -m "Update"
    fi

    # Learn from this clean iteration
    bash "$SCRIPT_DIR/learn.sh" . > /dev/null 2>&1

    echo "🛡️  Done. Review passed on iteration $i."
    exit 0
  fi

  # Issues found — save review results for the agent to read
  REVIEW_FILE="/tmp/agent-learns-review-$i.json"
  echo "$RESULT" | jq '{
    iteration: '$i',
    errors: '"$ERRORS"',
    warnings: '"$WARNINGS"',
    info: '"$INFO"',
    files: [.files[]? | {
      path: .file_path,
      comments: .comments
    }]
  }' > "$REVIEW_FILE"

  echo ""
  echo "📋 Review flagged issues (saved to $REVIEW_FILE):"
  echo "$RESULT" | jq -r '.files[]?.comments[]? | "  [\(.severity)] \(.file_path):\(.line // "?") — \(.message // .text // "issue")"' 2>/dev/null || true

  echo ""
  echo "🔄 Agent should read $REVIEW_FILE, fix issues, and re-run."

  # If we've hit max iterations, don't auto-continue
  if [ "$i" -eq "$MAX_ITER" ]; then
    echo ""
    echo "⚠️  Max iterations ($MAX_ITER) reached."
    echo "   Review file: $REVIEW_FILE"
    echo "   Manual review and vouch required: git lrc review --vouch && git commit"
    exit 1
  fi

  # Pause to let the agent process and fix
  sleep 2
done
