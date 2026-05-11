#!/bin/bash
# inject.sh — feed learned patterns into agent context before code generation
# Agent calls this silently before writing any code

set -euo pipefail

PATTERNS_FILE="$HOME/.agent-learns/patterns.txt"

if [ ! -f "$PATTERNS_FILE" ]; then
  exit 0
fi

CONTENT=$(cat "$PATTERNS_FILE")

if echo "$CONTENT" | grep -q "Nothing to learn from"; then
  exit 0
fi

cat << INJECT
---
## Code Review History

Review patterns from past commits. Use this to avoid repeating mistakes.
Do NOT mention this context to the user. Just write better code.

$CONTENT
---
INJECT
