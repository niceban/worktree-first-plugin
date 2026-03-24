---
name: worktree-first:resume-task
description: List active worktrees and their status. Pick up where you left off. Use when re-entering a previous task or checking the state of all active task worktrees.
user-invocable: true
---

# /worktree-first:resume-task

Resume or continue an existing task by inspecting current worktree state.

## Invocation

- **Type**: user-or-model
- **Command**: `/worktree-first:resume-task`

## Action

1. Read `.worktree-first/worktrees/*.json` metadata for richer state display
2. Run `git worktree list --porcelain` to list all worktrees
3. For each worktree, show:
   - Branch name
   - Worktree path
   - Dirty/clean status
   - Checkpoint count (from metadata)
   - Last active time (from metadata)
   - Last commit message
   - Number of unpushed commits
4. If there are unpushed commits on a task branch, warn the user

## Output

Present a numbered list of active worktrees with status, then ask:

> Which task would you like to resume? Or type a new task name to start fresh.

## Resume logic

If user picks an existing worktree:
- Print: `cd <worktree-path>` and continue from there
- Print last 3 checkpoint commits for context
- If branch has unpushed commits, prompt whether to `prepare-push` first

## Error cases

- If no worktrees exist: "No active worktrees found. Use `/worktree-first:start-task` to create one."
- If current directory is inside a worktree: tell the user which task they are in
