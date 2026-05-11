# Agent-Learns — Self-Improving Code Review for AI Agents

> Your agent reviews its own code. Learns from what it gets wrong. Gets better every commit.

## What It Does

AI agents write code fast. They also repeat mistakes. Same null checks missed. Same hardcoded values. Same missing error handling. Commit after commit.

**Agent-Learns closes the loop.** After every code change, Gemini reviews the diff. The agent reads the feedback, fixes issues, and re-runs until clean. Over time, the agent learns its own weak spots and stops repeating them.

No middleman. No signups. Just your Gemini key on your machine.

## Quick Start

```bash
# 1. Get a free Gemini key
#    https://aistudio.google.com/app/apikey

# 2. Save it
mkdir -p ~/.agent-learns
echo "GEMINI_KEY=your-key-here" > ~/.agent-learns/config

# 3. Install
git clone https://github.com/Pu11en/agent-learns.git
cd agent-learns
./install.sh
```

Your agent now reviews its own code before every commit.

## How It Works

```
Agent writes code
    ↓
loop.sh sends diff to Gemini API
    ↓
Gemini returns structured review (errors, warnings, info)
    ↓
If clean → commit with attestation
If issues → agent reads feedback, fixes, re-runs
    ↓
learn.sh reads history, extracts patterns
inject.sh feeds patterns back before next generation
```

After a few commits, the agent knows its weaknesses and commits clean first try.

## What You See (Almost Nothing)

```
Agent: 🔍 Reviewing... found 2 issues. Fixing.
       Re-reviewing... clean. ✅
```

After a few weeks:

```
Agent: Done. ✅
```

No popups. No reading. The agent absorbs the feedback.

## Files

| File | Purpose |
|---|---|
| `loop.sh` | Main engine — review → fix → re-review → commit |
| `learn.sh` | Reads attestation history, extracts patterns |
| `inject.sh` | Feeds patterns into agent context before generation |
| `install.sh` | One-command setup |
| `SKILL.md` | Hermes Agent / OpenClaw skill |

## Requirements

- Free Gemini API key (aistudio.google.com)
- Git repository
- Hermes Agent, OpenClaw, or any agent that runs shell commands

## License

MIT
