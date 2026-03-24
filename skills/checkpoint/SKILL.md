---
name: worktree-first:checkpoint
description: Create a local checkpoint commit after a meaningful intent boundary. Use frequently during development to save progress without polluting the commit history.
allowed-tools: Bash
---

# /worktree-first:checkpoint

Create a local checkpoint commit after a meaningful intent boundary.

## Invocation

- **Type**: model-allowed (only inside task worktree)
- **Command**: `/worktree-first:checkpoint`

## Pre-check

1. Must be inside a task worktree (not on `main`)
2. Must have staged changes (`git diff --cached --quiet` is not zero)
3. Must have a diff to review before committing

## Action

1. **AI Advisor** (P2): Call LLM to analyze staged diff and recommend whether this is commit-worthy + suggested message. Falls back to rule-based suggestion if LLM unavailable.
2. Show: `git status` and `git diff --stat`
3. Display AI or rule-based suggestion: `Suggested: checkpoint: <message>`
4. Ask user to confirm or edit the checkpoint message
5. Run:

```bash
git commit -m "checkpoint: <user message>"
```

6. Run lightweight validation:

```bash
make format 2>/dev/null || true
make lint 2>/dev/null || true
make test-quick 2>/dev/null || true
```

## Checkpoint message format

```
checkpoint: <what was achieved>
```

Examples:
- `checkpoint: auth timeout path now passes tests`
- `checkpoint: parser refactor compiles and passes smoke tests`
- `checkpoint: revert failed migration spike, keeping the old approach`

## Guard

If `git diff --cached --quiet` returns zero (nothing staged):
→ "Nothing staged. Run `git add -p <file>` or `git add <file>` first, then retry."

## Metadata

After successful commit, update `.worktree-first/worktrees/<slug>.json`:
- Append to `checkpoints[]` array
- Update `last_checkpoint_message`
- Update `last_active_at`
- Set `dirty: false`
