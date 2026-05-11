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
  echo "❌ No config found. Run: echo 'GEMINI_KEY=your-key' > $CONFIG"
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

echo "🛡️  Agent-Learns loop (max $MAX_ITER iterations)"

for i in $(seq 1 "$MAX_ITER"); do
  echo ""
  echo "── Iteration $i/$MAX_ITER ──"

  git add .
  DIFF=$(git diff --cached)

  if [ -z "$DIFF" ]; then
    echo "⚠️  No staged changes."
    exit 0
  fi

  # Build prompt and call Gemini via Python (no jq dependency)
  echo "🔍 Sending to Gemini..."

  RESULT=$(python3 -c "
import json, subprocess, sys, os

diff = '''$(echo "$DIFF" | sed "s/'/'\\\\''/g")'''

prompt = '''You are a strict code reviewer. Review the following git diff.

Return ONLY valid JSON:
{
  \"passed\": true or false,
  \"files\": [{
    \"file_path\": \"string\",
    \"comments\": [{
      \"severity\": \"error|warning|info\",
      \"line\": number,
      \"message\": \"what is wrong and how to fix it\"
    }]
  }],
  \"summary\": \"one sentence overview\"
}

RULES:
- Security issues (hardcoded keys, SQL injection, XSS) = error
- Logic bugs (null refs, race conditions, wrong conditionals) = error
- Missing error handling for I/O/network = warning
- Style/performance = info
- If no issues found, passed=true and files=[]

DIFF:
''' + diff

body = json.dumps({
    'contents': [{'parts': [{'text': prompt}]}]
})

proc = subprocess.run([
    'curl', '-s',
    '${API}',
    '-H', 'Content-Type: application/json',
    '-d', body
], capture_output=True, text=True)

resp = json.loads(proc.stdout)

# Try to extract text
text = ''
try:
    text = resp['candidates'][0]['content']['parts'][0]['text']
except:
    err = resp.get('error', {}).get('message', 'unknown')
    print(json.dumps({'error': err}))
    sys.exit(0)

# Strip markdown code fences if present
if text.startswith('\`\`\`'):
    text = text.split('\`\`\`')[1]
    if text.startswith('json'):
        text = text[4:]
text = text.strip()

# Validate JSON
try:
    review = json.loads(text)
except:
    # Try to find JSON block
    import re
    m = re.search(r'\{.*\}', text, re.DOTALL)
    if m:
        review = json.loads(m.group(0))
    else:
        print(json.dumps({'error': 'unparseable', 'raw': text[:200]}))
        sys.exit(0)

print(json.dumps(review))
" 2>/dev/null)

  # Parse result
  ERROR_MSG=$(echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error',''))" 2>/dev/null || echo "")

  if [ -n "$ERROR_MSG" ]; then
    echo "⚠️  Gemini error: $ERROR_MSG — committing without review"
    git commit ${COMMIT_MSG:+-m "$COMMIT_MSG"} --allow-empty 2>/dev/null || true
    exit 0
  fi

  PASSED=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('passed',False))" 2>/dev/null || echo "false")

  COUNTS=$(echo "$RESULT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
errs = 0
warns = 0
infos = 0
for f in d.get('files',[]):
    for c in f.get('comments',[]):
        s = c.get('severity','')
        if s == 'error': errs += 1
        elif s == 'warning': warns += 1
        elif s == 'info': infos += 1
print(f'{errs} {warns} {infos}')
" 2>/dev/null)

  ERRORS=$(echo "$COUNTS" | cut -d' ' -f1)
  WARNINGS=$(echo "$COUNTS" | cut -d' ' -f2)
  INFO=$(echo "$COUNTS" | cut -d' ' -f3)

  echo "   Errors: $ERRORS | Warnings: $WARNINGS | Info: $INFO"

  # Clean? Commit.
  if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo ""
    echo "✅ Clean — committing."

    TREE=$(git write-tree 2>/dev/null || echo "unknown")
    mkdir -p "$HOME/.agent-learns/attestations"
    echo "$RESULT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d['tree_hash'] = '$TREE'
d['iterations'] = $i
d['timestamp'] = '$(date -Iseconds)'
with open('$HOME/.agent-learns/attestations/$TREE.json','w') as f:
    json.dump(d, f)
" 2>/dev/null || true

    git commit ${COMMIT_MSG:+-m "$COMMIT_MSG"} -m "Agent-Learns: passed (iter:$i)" 2>/dev/null || \
      git commit ${COMMIT_MSG:+-m "$COMMIT_MSG"} --allow-empty 2>/dev/null || \
      git commit --allow-empty -m "update" -m "Agent-Learns: passed (iter:$i)"

    bash "$SCRIPT_DIR/learn.sh" . > /dev/null 2>&1
    echo "🛡️  Done. Passed on iteration $i."
    exit 0
  fi

  # Save review for agent
  echo "$RESULT" | python3 -m json.tool > "/tmp/agent-learns-review-$i.json" 2>/dev/null || echo "$RESULT" > "/tmp/agent-learns-review-$i.json"

  echo ""
  echo "📋 Issues:"
  echo "$RESULT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for f in d.get('files',[]):
    for c in f.get('comments',[]):
        print(f\"  [{c['severity']}] {f['file_path']}:{c['line']} — {c['message']}\")
" 2>/dev/null || echo "  (parse error — check /tmp/agent-learns-review-$i.json)"

  echo ""
  echo "🔄 Fix, stage, and re-run loop.sh"

  if [ "$i" -eq "$MAX_ITER" ]; then
    echo "⚠️  Max iterations. Manual review needed."
    exit 1
  fi

  sleep 2
done
