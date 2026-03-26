#!/usr/bin/env bash
# guard-main-write.sh — Block Edit/Write when on main branch
# Called on PreToolUse (Edit|Write|MultiEdit)
# stdin: tool input JSON
# exit 0 + JSON = deny (blocking)
# exit 0 without JSON = allow
#
# ARCHITECTURE:
# - Use CLAUDE_PROJECT_DIR as work_dir fallback (PWD may be reset to main)
# - In task worktree: always allow (worktree is isolated)

set -euo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

# Allow if no tool_name
[[ -z "$tool_name" ]] && exit 0

# =====================================================================
# Helper: Check if we are on the main branch (not a task branch)
# Priority: CLAUDE_PROJECT_DIR (if non-main) > PWD
# When PWD is main but CLAUDE_PROJECT_DIR is a task worktree, use it
# =====================================================================
is_on_main_branch() {
  local pwd_branch proj_dir proj_branch

  # Check PWD branch
  pwd_branch=$(git -C "$PWD" symbolic-ref --short HEAD 2>/dev/null || echo "unknown")

  # If PWD is already non-main, trust it
  [[ "$pwd_branch" != "main" ]] && [[ "$pwd_branch" != "unknown" ]] && return 1

  # PWD is main — check CLAUDE_PROJECT_DIR as fallback
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    proj_dir="${CLAUDE_PROJECT_DIR}"
    if git -C "$proj_dir" rev-parse --show-toplevel &>/dev/null; then
      proj_branch=$(git -C "$proj_dir" symbolic-ref --short HEAD 2>/dev/null || echo "")
      [[ "$proj_branch" != "main" ]] && return 1
    fi
  fi

  # Both are main (or unknown)
  return 0
}

# =====================================================================
# Core Logic: Only block on main branch
# =====================================================================
if ! is_on_main_branch; then
  # On a task branch - always allow (worktree is isolated)
  exit 0
fi

# In main worktree - block Edit/Write/MultiEdit
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "Cannot edit/write files in main worktree. Use /worktree-first:start-task to create a task worktree first."
  }
}'
exit 0
