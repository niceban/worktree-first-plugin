---
name: worktree-first:doctor
description: Audit all worktrees, find orphaned/stale/dirty ones, and report branch hygiene issues. Read-only by default — suggests fixes but does not auto-execute destructive actions.
user-invocable: true
allowed-tools: Bash
---

# /worktree-first:doctor

Audit all worktrees, find orphaned/stale/dirty ones, and report branch hygiene issues.

## Invocation

- **Type**: user-or-model (read-only diagnostics)
- **Command**: `/worktree-first:doctor`

## Action

Run a full audit and report findings by category.

### 1. Worktree audit

```bash
git worktree list --porcelain
```

For each worktree report:
- Path, branch, HEAD commit
- Dirty/clean status
- Age (last commit time)

Flag:
- `ORPHANED`: worktree exists but branch no longer exists
- `STALE`: no activity > 7 days
- `DIRTY`: has uncommitted changes and no recent commits
- `UNTRACKED`: no matching remote branch

### 2. Remote branch audit

```bash
git branch -r --list 'task/*'
```

Flag branches:
- No local worktree (branch exists remotely but no worktree)
- Remote-only branches that were likely merged and abandoned

### 3. Commit hygiene

```bash
git log --oneline -10   # recent commits
git log --oneline origin/main..HEAD   # unpushed commits
```

Flag:
- Checkpoint-only branches that were never cleaned up
- Branches with > 20 checkpoint commits without a review commit

### 4. Overall report format

```
=== Worktree Audit ===
[OK]    wt/auth-timeout      clean, branch task/fix-auth-timeout
[WARN]  wt/search-index      dirty (3 uncommitted files, last commit 5 days ago)
[ORPHAN] wt/old-spike       branch deleted but worktree not removed

=== Remote Branch Audit ===
[OK]    origin/task/feat-search-index
[STALE] origin/task/spike-pipeline   (no push in 14 days, likely abandoned)

=== Recommendations ===
1. Run `git worktree remove ../wt/old-spike` to clean orphaned worktree
2. Confirm `wt/search-index` status — commit or discard before continuing
3. Delete or finish `origin/task/spike-pipeline`
```

## Behavior

- **Default: read-only**. Does not modify anything.
- If user explicitly asks to fix something, prompt for confirmation before any destructive action.
- Exits with code 0 if no issues found, 1 if warnings found, 2 if errors found.
