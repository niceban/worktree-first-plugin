---
name: worktree-first:select-worktree
description: Interactively select an existing worktree or create a new one. Shows all active worktrees with their status, checkpoint count, and last active time. Use when starting a session or resuming work.
user-invocable: true
---

# /worktree-first:select-worktree

Interactively select a worktree or start a new task.

## Invocation

- **Type**: user-or-model
- **Command**: `/worktree-first:select-worktree`

## Action

1. Read all `.worktree-first/worktrees/*.json` metadata files
2. Display a numbered list of active worktrees with:
   - Index number
   - Slug (worktree name)
   - Dirty/clean status
   - Checkpoint count
   - Last active time (relative: "2h ago", "5m ago", etc.)
3. Add an extra option: `[N] Start new task`
4. Prompt: `Pick a number or type a new task name: `
5. Read user input

## Input Handling

| Input | Behavior |
|-------|----------|
| `1` or `2` (valid index) | Output worktree path + `cd <path> && claude` instructions |
| `3` (start new task) | Output guidance: `/worktree-first:start-task <type> <slug>` |
| Any other text | Treat as new task slug; output start-task guidance with that slug |

## Output Examples

```
=== Select Worktree ===
  [1] search-index  dirty  3 checkpoints  last: 2h ago
  [2] auth-fix      clean  1 checkpoint   last: 5m ago
  [3] Start new task

Pick a number or type a new task name: 1

Selected: search-index

Worktree path: /Users/c/auto-git/worktree-first/wt/search-index

Next: cd /Users/c/auto-git/worktree-first/wt/search-index && claude
```

## Error cases

- If no worktrees exist: show message pointing to `/worktree-first:start-task`
- If metadata is corrupt: skip that entry and continue
- If input is invalid number: print error and exit 1

## Tools

- **Bash**: Used to run `select-worktree.sh` script
