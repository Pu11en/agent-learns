# Agent-Learns — Self-Improving Code Review for AI Agents

> Your agent reviews its own code. Learns from what it gets wrong. Gets better every commit.

## What It Does

AI agents write code fast. They also repeat the same mistakes. Missed null checks in async handlers. Hardcoded values in components. Missing error handling. Same patterns, commit after commit.

**Agent-Learns closes the loop.** It wraps [git-lrc](https://github.com/HexmosTech/git-lrc) so that every review result becomes feedback the agent learns from — not just a popup you have to read.

### The Loop

```
Agent writes code
    ↓
git-lrc reviews it          ← catches issues inline
    ↓
Agent reads review output   ← understands what went wrong
    ↓
Agent fixes issues           ← auto-patches
    ↓
Re-review until clean        ← gate stays up until clean
    ↓
Learn from results           ← patterns saved, fed back next time
```

After a few commits, the agent:
- Knows its own weak spots
- Avoids repeating the same mistakes
- Needs fewer review iterations to pass
- Eventually commits clean on first try

## Quick Start

```bash
# 1. Install git-lrc (one time)
curl -fsSL https://hexmos.com/lrc-install.sh | bash
git lrc setup

# 2. Clone agent-learns
git clone https://github.com/yourname/agent-learns.git
cd agent-learns
chmod +x *.sh

# 3. Wire into your agent
```

### For Hermes Agent / OpenClaw

Copy `SKILL.md` into your agent's skills directory. When code generation completes, the agent automatically runs the review loop.

### Manual / Any Agent

```bash
# Agent generates code, then:
./loop.sh 5 "add dark mode toggle"
```

That's it. The loop handles review, fixes, learning, and commit.

## How It Feels

### First few commits
```
You: add payment validation

Agent: Got it. [writes code]
       🔍 Reviewing... found 2 issues. Fixing.
       🔍 Re-reviewing... clean. ✅
       Learned: watch null checks in payment handlers.
```

### After 10 commits
```
You: add subscription billing

Agent: On it. (I've been flagged for null checks here before — handling those.)
       [writes code]
       🔍 Clean. ✅
```

### After a month
```
You: refactor billing system
Agent: Done. ✅
```

No popups. No reading. The agent absorbed its weaknesses.

## Files

| File | Purpose |
|---|---|
| `loop.sh` | Main review loop — review → fix → re-review → commit |
| `learn.sh` | Reads past reviews, finds patterns, saves summary |
| `inject.sh` | Feeds learned patterns into agent context before generation |
| `SKILL.md` | Hermes Agent / OpenClaw skill configuration |

## Prerequisites

- [git-lrc](https://github.com/HexmosTech/git-lrc) installed and set up
- A git repository
- An AI coding agent (Hermes, OpenClaw, Claude Code, etc.)

## How It Works

1. **learn.sh** scans `.git/lrc/attestations/` and git log for review history, extracts pattern summaries
2. **inject.sh** feeds those patterns to the agent as silent context before code generation
3. **loop.sh** orchestrates: generate → review → parse issues → fix → re-review → learn → commit

The agent doesn't just pass review — it gets better at passing review over time.

## License

MIT — do whatever you want with it.
