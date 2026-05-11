#!/bin/bash
# install.sh — one-command setup for agent-learns
set -euo pipefail

echo "🛡️  Agent-Learns Installer"
echo ""

# Check git-lrc
if ! command -v git-lrc &>/dev/null; then
  echo "📦 Installing git-lrc..."
  curl -fsSL https://hexmos.com/lrc-install.sh | bash
  echo ""
  echo "🔑 Run 'git lrc setup' to configure your API keys, then re-run this installer."
  exit 0
fi

echo "✅ git-lrc found: $(git-lrc version 2>/dev/null || echo 'installed')"

# Make scripts executable
chmod +x "$(dirname "$0")"/*.sh 2>/dev/null || true

# Create patterns directory
mkdir -p "$HOME/.agent-learns"

# Detect agent and install skill
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -d "$HOME/.hermes/skills" ]; then
  cp "$SCRIPT_DIR/SKILL.md" "$HOME/.hermes/skills/agent-learns.md"
  echo "✅ Installed Hermes Agent skill"
elif [ -d "$HOME/.openclaw/skills" ]; then
  cp "$SCRIPT_DIR/SKILL.md" "$HOME/.openclaw/skills/agent-learns.md"
  echo "✅ Installed OpenClaw skill"
elif [ -d "$HOME/.claude/skills" ]; then
  cp "$SCRIPT_DIR/SKILL.md" "$HOME/.claude/skills/agent-learns.md"
  echo "✅ Installed Claude Code skill"
else
  echo "ℹ️  No agent skills directory found. Copy SKILL.md manually to your agent's skills folder."
fi

echo ""
echo "🛡️  Agent-Learns is ready."
echo ""
echo "   Usage: ./loop.sh 5 \"your commit message\""
echo ""
echo "   Or just let your agent handle it — the skill is configured."
