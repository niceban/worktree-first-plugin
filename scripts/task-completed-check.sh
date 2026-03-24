#!/usr/bin/env bash
# task-completed-check.sh — Block TaskCompleted if preconditions not met
# Called on TaskCompleted hook
# exit 0 = allow, exit 0 + JSON deny = block

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$PROJECT_DIR" ]] && exit 0

cd "$PROJECT_DIR"

current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

# BLOCK: if on main
if [[ "$current_branch" == "main" ]]; then
  jq -n '{ hookSpecificOutput: { hookEventName: "TaskCompleted", permissionDecision: "deny", permissionDecisionReason: "Cannot complete task while on main. Switch to a task branch." }}'
  exit 0
fi

# BLOCK: if dirty
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  jq -n '{ hookSpecificOutput: { hookEventName: "TaskCompleted", permissionDecision: "deny", permissionDecisionReason: "Uncommitted changes remain. Commit or discard them first." }}'
  exit 0
fi

# BLOCK: if branch has never been pushed at all
# At least one push is required before completion
if ! git rev-parse --verify "origin/${current_branch}" &>/dev/null; then
  jq -n '{ hookSpecificOutput: { hookEventName: "TaskCompleted", permissionDecision: "deny", permissionDecisionReason: "This branch has never been pushed. Push with /worktree-first:prepare-push before marking complete." }}'
  exit 0
fi

# BLOCK: if behind origin/main (main has moved, branch not rebased)
behind=0
git fetch origin &>/dev/null
if ! git diff --quiet origin/main..HEAD 2>/dev/null; then
  # Branch has diverged from main
  behind=1
fi

if [[ "$behind" -eq 1 ]]; then
  jq -n '{ hookSpecificOutput: { hookEventName: "TaskCompleted", permissionDecision: "deny", permissionDecisionReason: "Branch has diverged from main. Rebase onto latest main with /worktree-first:prepare-push before completing." }}'
  exit 0
fi

# BLOCK: if last commit is a checkpoint (not reviewed yet)
last_msg=$(git log -1 --format="%s" HEAD 2>/dev/null || true)
if [[ "$last_msg" =~ ^checkpoint: ]]; then
  jq -n '{ hookSpecificOutput: { hookEventName: "TaskCompleted", permissionDecision: "deny", permissionDecisionReason: "Last commit is a checkpoint and has not been reviewed. Run /worktree-first:prepare-push to clean history before completing." }}'
  exit 0
fi

exit 0
