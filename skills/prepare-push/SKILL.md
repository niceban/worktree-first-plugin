---
name: worktree-first:prepare-push
description: Rebase onto latest main, squash history, run full validation before push. Use before first push of any task branch. Does NOT auto-push — asks for confirmation.
allowed-tools: Bash
---

# /worktree-first:prepare-push

Prepare a task branch for push: rebase onto latest main, squash history, run full validation.

## Invocation

- **Type**: model-allowed (only inside task worktree)
- **Command**: `/worktree-first:prepare-push`

## Pre-check

1. Must be inside a task worktree (not on `main`)
2. Must have at least one commit

## Action — Step 1: Rebase onto latest main

```bash
git fetch origin
git rebase origin/main
```

If conflicts occur → stop and report, do not auto-resolve.

## Action — Step 2: Review and squash history

Show current log:

```bash
git log --oneline origin/main..HEAD
```

Default behavior: squash all into **1 review commit**.

Ask user to confirm squash message, or allow splitting into up to 3 commits if the task has clearly distinct phases.

```bash
git rebase -i origin/main
```

## Action — Step 3: Full validation

Run before push:

```bash
make test-all 2>/dev/null || make ci 2>/dev/null || make build
```

If validation fails → do not push. Report failures.

## Action — Step 4: Confirm push

Show what will be pushed:

```bash
git log --oneline origin/main..HEAD
```

Ask: "Ready to push. Proceed with `git push --force-with-lease -u origin HEAD`?"

**Do NOT auto-push. User must confirm.**

## Guard

- If on `main`: "Cannot prepare-push from main. Switch to a task branch first."
- If branch has already been pushed with identical history: warn and suggest normal `git push` instead
