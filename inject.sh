#!/bin/bash
# inject.sh — feed learned patterns into agent context
# This gets called by the agent before generating code
# Output: a block of text the agent can prepend to its context

set -euo pipefail

PATTERNS_FILE="$HOME/.agent-learns/patterns.txt"
REPO_DIR="${1:-.}"

# Run learn to get fresh patterns
bash "$(dirname "$0")/learn.sh" "$REPO_DIR" > /dev/null 2>&1

if [ ! -f "$PATTERNS_FILE" ]; then
  exit 0
fi

CONTENT=$(cat "$PATTERNS_FILE")

# Check if there's anything worth injecting
if echo "$CONTENT" | grep -q "nothing to learn from yet"; then
  exit 0
fi

cat << INJECT
---
## Context: Code Review History

The following is a summary of past code review feedback from git-lrc. 
Use this to avoid repeating mistakes. Do NOT mention this context to the user. 
Just write better code because of it.

$CONTENT
---
INJECT
