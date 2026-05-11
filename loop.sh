#!/bin/bash
# loop.sh — autonomous review loop (direct Gemini, no middleman)
# Usage: ./loop.sh [max-iterations] ["commit message"]
set -euo pipefail

MAX_ITER="${1:-5}"
COMMIT_MSG="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$HOME/.agent-learns/config"

# ── Load API key ──
if [ ! -f "$CONFIG" ]; then
  echo "❌ No Gemini API key found."
  echo "   Get one at: https://aistudio.google.com/app/apikey"
  echo "   Then run: mkdir -p ~/.agent-learns && echo 'GEMINI_KEY=your-key' > ~/.agent-learns/config"
  exit 1
fi
source "$CONFIG"

if [ -z "${GEMINI_KEY:-}" ]; then
  echo "❌ GEMINI_KEY not set in $CONFIG"
  exit 1
fi

API="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_KEY"

# ── Git check ──
if ! git rev-parse --git-dir &>/dev/null; then
  echo "❌ Not a git repo"
  exit 1
fi

echo "🛡️  Agent-Learns loop starting (max $MAX_ITER iterations)"

for i in $(seq 1 "$MAX_ITER"); do
  echo ""
  echo "── Iteration $i/$MAX_ITER ──"

  git add .
  DIFF=$(git diff --cached)

  if [ -z "$DIFF" ]; then
    echo "⚠️  No staged changes. Nothing to review."
    exit 0
  fi

  # Build review request
  PROMPT=$(jq -n --arg diff "$DIFF" '{
    contents: [{
      parts: [{
        text: "You are a strict code reviewer. Review the following git diff.\n\nReturn ONLY valid JSON:\n{\n  \"passed\": true or false,\n  \"files\": [{\n    \"file_path\": \"string\",\n    \"comments\": [{\n      \"severity\": \"error|warning|info\",\n      \"line\": number,\n      \"message\": \"what is wrong and how to fix it\"\n    }]\n  }],\n  \"summary\": \"one sentence overview\"\n}\n\nRULES:\n- Security issues (hardcoded keys, SQL injection, XSS) = error\n- Logic bugs (null refs, race conditions, wrong conditionals) = error\n- Missing error handling for I/O/network = warning\n- Style/performance = info\n- If no issues found, passed=true and files=[]\n\nDIFF:\n\($diff)"
      }]
    }]
  }')

  echo "🔍 Sending to Gemini..."

  RESPONSE=$(curl -s "$API" \
    -H "Content-Type: application/json" \
    -d "$PROMPT" 2>/dev/null)

  # Extract the text response
  TEXT=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text // ""' 2>/dev/null)

  if [ -z "$TEXT" ]; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error.message // "unknown"' 2>/dev/null)
    echo "⚠️  Gemini error: $ERROR — continuing without review"
    git commit ${COMMIT_MSG:+-m "$COMMIT_MSG"} --allow-empty 2>/dev/null || true
    exit 0
  fi

  # Try to parse the JSON from Gemini's response (strip markdown if wrapped)
  CLEAN=$(echo "$TEXT" | sed -n '/^{/,/^}/p' | head -1)
  if [ -z "$CLEAN" ]; then
    CLEAN="$TEXT"
  fi

  PASSED=$(echo "$CLEAN" | jq -r '.passed // false' 2>/dev/null || echo "false")
  ERRORS=$(echo "$CLEAN" | jq '[.files[]?.comments[]? | select(.severity=="error")] | length' 2>/dev/null || echo "0")
  WARNINGS=$(echo "$CLEAN" | jq '[.files[]?.comments[]? | select(.severity=="warning")] | length' 2>/dev/null || echo "0")
  INFO=$(echo "$CLEAN" | jq '[.files[]?.comments[]? | select(.severity=="info")] | length' 2>/dev/null || echo "0")
  SUMMARY=$(echo "$CLEAN" | jq -r '.summary // ""' 2>/dev/null || echo "")

  echo "   Errors: $ERRORS | Warnings: $WARNINGS | Info: $INFO"

  if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo ""
    echo "✅ Clean review — committing."
    echo "$CLEAN" | jq '.' > "/tmp/agent-learns-clean.json"

    # Write attestation
    TREE=$(git write-tree 2>/dev/null || echo "unknown")
    mkdir -p "$HOME/.agent-learns/attestations"
    jq -n --arg tree "$TREE" --arg iter "$i" --arg time "$(date -Iseconds)" '{
      tree_hash: $tree,
      iterations: ($iter | tonumber),
      passed: true,
      timestamp: $time
    }' > "$HOME/.agent-learns/attestations/$TREE.json" 2>/dev/null || true

    # Commit with attestation trailer
    if [ -n "$COMMIT_MSG" ]; then
      git commit -m "$COMMIT_MSG" -m "Agent-Learns: passed (iter:$i)" --allow-empty 2>/dev/null || git commit -m "$COMMIT_MSG" --allow-empty
    else
      git commit -m "Update" -m "Agent-Learns: passed (iter:$i)" --allow-empty 2>/dev/null || git commit --allow-empty -m "Update"
    fi

    # Learn from this session
    bash "$SCRIPT_DIR/learn.sh" . > /dev/null 2>&1

    echo "🛡️  Done. Passed on iteration $i."
    exit 0
  fi

  # Issues found — save for agent to read
  REVIEW_FILE="/tmp/agent-learns-review-$i.json"
  echo "$CLEAN" | jq '.' > "$REVIEW_FILE"

  echo ""
  echo "📋 Issues found:"
  echo "$CLEAN" | jq -r '.files[]?.comments[]? | "  [\(.severity)] \(.file_path):\(.line) — \(.message)"' 2>/dev/null || echo "  (could not parse comments)"

  if [ "$SUMMARY" != "" ] && [ "$SUMMARY" != "null" ]; then
    echo "   📝 $SUMMARY"
  fi

  echo ""
  echo "🔄 Fix the issues above, stage changes, and this loop will continue."

  if [ "$i" -eq "$MAX_ITER" ]; then
    echo ""
    echo "⚠️  Max iterations reached. Review file: $REVIEW_FILE"
    echo "   Manual review needed before commit."
    exit 1
  fi

  # Pause for agent to fix
  sleep 2
done
