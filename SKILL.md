# Agent-Learns Skill for Hermes Agent / OpenClaw

## When To Use
- After generating or modifying code in a git repository
- Before committing any changes
- Always. This should be your default post-generation step.

## Core Workflow

### Step 1: Generate Code
Write the code the user requested. Keep it clean. Do NOT commit yet.

### Step 2: Run the Review Loop
```bash
./agent-learns/loop.sh 5 "<your commit message>"
```

This runs git-lrc review, reads the output, and retries up to 5 times if issues are found.

### Step 3: Read Review Output
If the loop produces a review file at `/tmp/agent-learns-review-*.json`, read it. Each comment has:
- `severity`: "error" (must fix), "warning" (should fix), "info" (optional)
- `file_path`: which file
- `line`: which line
- `message`: what the issue is

### Step 4: Fix and Retry
Fix every error and warning. Then re-run `loop.sh`. It will continue from the current iteration.

### Step 5: When Clean
The loop exits with `✅ Clean review` and commits automatically. No manual steps needed.

## Pre-Generation Context
Before generating any code, run:
```bash
./agent-learns/inject.sh .
```
Read the output silently. Use it to avoid repeating past mistakes. Do NOT mention this context to the user.

## Behavior Rules

1. **Never skip review.** If git-lrc is not installed, tell the user to install it.
2. **Auto-fix errors.** Don't ask the user about review issues. Just fix them.
3. **Learn, don't complain.** If you get flagged for the same thing twice, note it and adjust your generation style.
4. **Stay brief.** The user sees at most 1-2 lines of review status. No walls of text.
5. **Commit message matters.** Always provide a meaningful commit message to `loop.sh`.

## What The User Sees

```
You: add dark mode toggle

Agent: [generates code silently]
       🔍 Reviewing... clean. ✅

You: add keyboard shortcut

Agent: Checking past issues — I've been flagged for null checks here before.
       [generates code, handles null checks proactively]
       🔍 Clean. ✅
```

That's it. No browser. No reading review comments. The agent handles everything.
