---
name: worktree-first:finish-task
description: Clean up after a task is merged or abandoned — remove worktree, delete local and remote branches. Destructive operation — only for manual invocation.
disable-model-invocation: true
argument-hint: [merged|abandoned]
---

# /worktree-first:finish-task

Clean up after a task is merged or abandoned: remove worktree, delete branches.

## Invocation

- **Type**: user-only (destructive — no model auto-invocation)
- **Command**: `/worktree-first:finish-task [merged|abandoned]`

## Pre-check

1. Must be inside a task worktree (not on `main`)
2. Must confirm: is this task merged or abandoned?

## Cleanup steps

### If merged (PR is closed + merged on GitHub):

```bash
# Delete metadata file
rm .worktree-first/worktrees/<slug>.json

# Remove worktree
git worktree remove ../wt/<slug>

```bash
# Remove worktree
git worktree remove ../wt/<slug>

# Delete local branch
git branch -d task/<type>-<slug>

# Delete remote branch
git push origin --delete task/<type>-<slug>
```

### If abandoned (PR closed without merging):

```bash
# Warn about unpushed commits
git log origin/main..HEAD --oneline

# Ask: "There are unpushed commits. Delete anyway?"

# Remove worktree
git worktree remove ../wt/<slug>

# Delete local branch (force, since not merged)
git branch -D task/<type>-<slug>

# Delete remote branch
git push origin --delete task/<type>-<slug>
```

## Guard

- If on `main`: "finish-task can only be run from inside a task worktree."
- If worktree is dirty (uncommitted changes): "Worktree has uncommitted changes. Commit, stash, or discard them first."
- If worktree is locked: "Worktree is locked. Unlock with `git worktree unlock <path>` first."

## Output

Report what was deleted and confirm the worktree list is now clean.
