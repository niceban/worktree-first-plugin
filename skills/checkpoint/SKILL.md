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

1. Show: `git status` and `git diff --stat`
2. Ask user to confirm or edit the checkpoint message
3. Run:

```bash
git commit -m "checkpoint: <user message>"
```

4. Run lightweight validation:

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

## Output

Confirm the commit hash and message, then show `git log --oneline -3`.
