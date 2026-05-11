#!/bin/bash
# install.sh — one command, everything set up
# Clone this repo, run ./install.sh, done.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.agent-learns"

echo "🛡️  Agent-Learns Installer"
echo ""

# Step 1: Check for Gemini key
if [ ! -f "$HOME/.agent-learns/config" ]; then
  echo "📝 No Gemini key found."
  echo ""
  echo "   Get a free key: https://aistudio.google.com/app/apikey"
  echo "   Then: mkdir -p ~/.agent-learns"
  echo "   Then: echo \"GEMINI_KEY=your-key\" > ~/.agent-learns/config"
  echo ""
  echo "   Re-run ./install.sh after."
  exit 0
fi

source "$HOME/.agent-learns/config"
if [ -z "${GEMINI_KEY:-}" ]; then
  echo "❌ GEMINI_KEY empty in ~/.agent-learns/config"
  exit 1
fi

echo "✅ Gemini key found"

# Step 2: Clone scripts if not already done
if [ ! -f "$INSTALL_DIR/loop.sh" ]; then
  echo "📁 Installing scripts..."
  git clone https://github.com/Pu11en/agent-learns.git "$INSTALL_DIR" 2>/dev/null || \
    cp -r "$SCRIPT_DIR" "$INSTALL_DIR"
fi
chmod +x "$INSTALL_DIR"/*.sh

# Step 3: Install Hermes skill
installed=false

if ls -d "$HOME"/.hermes/profiles/*/skills/ 2>/dev/null 1>&2; then
  for skills_dir in "$HOME"/.hermes/profiles/*/skills/; do
    dest="$skills_dir/software-development/agent-learns"
    mkdir -p "$dest"
    cp "$SCRIPT_DIR/SKILL.md" "$dest/SKILL.md"
    echo "✅ Installed to $(basename $(dirname $(dirname $skills_dir))) profile"
  done
  installed=true
fi

if [ -d "$HOME/.hermes/skills" ]; then
  dest="$HOME/.hermes/skills/software-development/agent-learns"
  mkdir -p "$dest"
  cp "$SCRIPT_DIR/SKILL.md" "$dest/SKILL.md"
  echo "✅ Installed to global Hermes skills"
  installed=true
fi

if [ "$installed" = false ]; then
  echo "ℹ️  No Hermes detected. SKILL.md at $SCRIPT_DIR/SKILL.md — copy manually."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🛡️  Agent-Learns ready."
echo ""
echo "   Your agent now reviews its own code"
echo "   using Gemini before every commit."
echo ""
echo "   Scripts: $INSTALL_DIR/"
echo "   Config:  ~/.agent-learns/config"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
