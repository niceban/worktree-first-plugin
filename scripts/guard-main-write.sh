#!/usr/bin/env bash
# guard-main-write.sh — Block Edit/Write when on main or outside task worktree
# Called on PreToolUse (Edit|Write|MultiEdit)
# stdin: tool input JSON
# exit 0 + JSON = deny (JSON parsed, tool blocked)
# exit 0 without JSON = allow

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$PROJECT_DIR" ]] && exit 0

cd "$PROJECT_DIR"

current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

# Allow if we can't determine branch
[[ -z "$current_branch" ]] && exit 0

# BLOCK: on main branch — exit 0 + JSON deny
if [[ "$current_branch" == "main" ]]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Cannot edit/write files while on main branch. Use /worktree-first:start-task to create a task worktree first."
    }
  }'
  exit 0
fi

# BLOCK: on a task branch but NOT inside a worktree directory (in the main repo dir)
is_main_worktree=false
if [[ "$(pwd)" == "$PROJECT_DIR" ]]; then
  is_main_worktree=true
fi

if [[ "$is_main_worktree" == "true" ]] && [[ "$current_branch" =~ ^task/ ]]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "You are on a task branch but still in the main worktree directory. Switch to your task worktree with: cd ../wt/<slug>"
    }
  }'
  exit 0
fi

exit 0
