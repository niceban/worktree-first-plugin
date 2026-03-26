---
name: worktree-first:start-task
description: Create a new task branch + worktree from origin/main. Use when starting a new feature, fix, refactor, or spike. Destructive by nature — only for manual invocation.
disable-model-invocation: true
argument-hint: <type> <slug>
---

# /worktree-first:start-task

Create a new task branch + worktree from `origin/main`.

## Invocation

- **Type**: user-only (disable model auto-invocation)
- **Command**: `/worktree-first:start-task <type> <slug>`

## Arguments

- `type`: `feat` | `fix` | `refactor` | `spike` | `chore`
- `slug`: short descriptive name (kebab-case)

## Pre-check

1. Must be inside a Git repository
2. `origin/main` must exist
3. Cannot run if current branch is `main` and has uncommitted changes (stash first)
4. Check if a worktree for this task already exists — if so, prompt user to use `/worktree-first:resume-task` instead

## Action

```bash
# Sync main first
git switch main && git fetch origin && git pull --ff-only

# Create branch + worktree
git worktree add -b "task/<type>-<slug>" "../wt/<slug>" origin/main
```

Then set per-worktree config:

```bash
git -C "../wt/<slug>" config --worktree rerere.enabled true
git -C "../wt/<slug>" config --worktree branch.autosetuprebase always
```

## Output

- Confirm new branch name and worktree path
- Tell user: `cd ../wt/<slug>` then launch Claude there
- Remind user of naming: `checkpoint:` prefix for local commits

## Error cases

- If worktree already exists: "A worktree for this task already exists at `../wt/<slug>`. Use `/worktree-first:resume-task` instead."
- If `origin/main` not found: "No `origin/main` found. Ensure the remote is configured."
- If uncommitted changes on main: "Stash or commit changes on main first, then retry."

## Auto-Worktree Behavior (Guard)

When you attempt to Edit, Write, MultiEdit, or run dangerous Bash commands while on the `main` branch, the guard hook will automatically:

1. Create a new worktree at `../wt/<slug>` with a task branch
2. Configure it with rerere and autosetuprebase
3. Create metadata in `.worktree-first/worktrees/<slug>.json`
4. Show a message explaining where the worktree was created and how to switch

This means you can seamlessly continue your work without manually creating a worktree first. Just use `/worktree-first:start-task` to explicitly create a named worktree, or let the guard auto-create one if you forget.
