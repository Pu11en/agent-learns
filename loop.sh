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
  echo "❌ No config. Run: echo 'GEMINI_KEY=your-key' > $CONFIG"
  exit 1
fi
source "$CONFIG"

if [ -z "${GEMINI_KEY:-}" ]; then
  echo "❌ GEMINI_KEY not set in $CONFIG"
  exit 1
fi

API="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_KEY"

if ! git rev-parse --git-dir &>/dev/null; then
  echo "❌ Not a git repo"
  exit 1
fi

echo "🛡️  Agent-Learns loop (max $MAX_ITER iterations)"

for i in $(seq 1 "$MAX_ITER"); do
  echo ""
  echo "── Iteration $i/$MAX_ITER ──"

  git add .
  DIFF_FILE=$(mktemp)
  git diff --cached > "$DIFF_FILE"

  if [ ! -s "$DIFF_FILE" ]; then
    echo "⚠️  No staged changes."
    rm -f "$DIFF_FILE"
    exit 0
  fi

  echo "🔍 Sending to Gemini..."

  python3 -c "
import subprocess, json, sys

GEMINI_KEY = '${GEMINI_KEY}'
API = f'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={GEMINI_KEY}'

with open('${DIFF_FILE}') as f:
    diff = f.read()

prompt = '''You are a strict code reviewer. Review this git diff.

Return ONLY valid JSON (no markdown, no explanation):
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
  \"summary\": \"one sentence\"
}

RULES:
- Hardcoded secrets/API keys/passwords = error
- SQL injection, XSS, shell injection = error
- Null references, race conditions, logic bugs = error
- Missing error handling for I/O/network = warning
- Style/naming/performance = info
- If clean: passed=true, files=[]

DIFF:
''' + diff

body = json.dumps({
    'contents': [{'parts': [{'text': prompt}]}]
})

proc = subprocess.run(['curl', '-s', API, '-H', 'Content-Type: application/json', '-d', body],
                       capture_output=True, text=True, timeout=45)
resp = json.loads(proc.stdout)

try:
    text = resp['candidates'][0]['content']['parts'][0]['text']
except:
    err = resp.get('error', {}).get('message', 'unknown')
    print(json.dumps({'error': err}))
    sys.exit(0)

# Strip markdown fences
t = text.strip()
if t.startswith('\`\`\`'):
    lines = t.split('\n')
    t = '\n'.join(lines[1:-1] if len(lines) > 2 else lines[1:])
    if t.startswith('json'):
        t = t[4:].strip()

try:
    review = json.loads(t)
except:
    import re
    m = re.search(r'\{.*\}', t, re.DOTALL)
    review = json.loads(m.group(0)) if m else {'error': 'unparseable', 'raw': t[:200]}

print(json.dumps(review))
" > /tmp/agent-learns-result.json 2>/dev/null

  rm -f "$DIFF_FILE"

  RESULT=$(cat /tmp/agent-learns-result.json)

  ERROR_MSG=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('error',''))" 2>/dev/null || echo "")

  if [ -n "$ERROR_MSG" ]; then
    echo "⚠️  Gemini error: $ERROR_MSG — committing without review"
    git commit ${COMMIT_MSG:+-m "$COMMIT_MSG"} --allow-empty 2>/dev/null || true
    exit 0
  fi

  PASSED=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('passed',False))" 2>/dev/null || echo "false")

  COUNTS=$(echo "$RESULT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
errs = warns = infos = 0
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

  if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo ""
    echo "✅ Clean review — committing."
    TREE=$(git write-tree 2>/dev/null || echo "unknown")
    mkdir -p "$HOME/.agent-learns/attestations"
    if [ "$TREE" != "unknown" ]; then
      cp /tmp/agent-learns-result.json "$HOME/.agent-learns/attestations/$TREE.json"
    fi
    git commit ${COMMIT_MSG:+-m "$COMMIT_MSG"} -m "Agent-Learns: passed (iter:$i)" 2>/dev/null || \
      git commit ${COMMIT_MSG:+-m "$COMMIT_MSG"} --allow-empty 2>/dev/null || \
      git commit --allow-empty -m "update" -m "Agent-Learns: passed (iter:$i)"
    bash "$SCRIPT_DIR/learn.sh" . > /dev/null 2>&1
    echo "🛡️  Done."
    exit 0
  fi

  cp /tmp/agent-learns-result.json "/tmp/agent-learns-review-$i.json"

  echo ""
  echo "📋 Review issues:"
  echo "$RESULT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for f in d.get('files',[]):
    for c in f.get('comments',[]):
        print(f\"  [{c['severity']}] {f['file_path']}:{c['line']} — {c['message']}\")
" 2>/dev/null || echo "  (check /tmp/agent-learns-review-$i.json)"

  echo ""
  echo "🔄 Fix the issues, stage changes, and re-run loop.sh"

  if [ "$i" -eq "$MAX_ITER" ]; then
    echo "⚠️  Max iterations. Manual review needed."
    exit 1
  fi
  sleep 2
done
