#!/usr/bin/env bash
# guard-bash.sh — Block dangerous Bash commands
# Called on PreToolUse (Bash)
# stdin: tool input JSON
# exit 0 + JSON deny = blocked; exit 0 (no JSON) = allowed
#
# ARCHITECTURE (D1+D2+D4+D5+D6+D7):
# - NEVER cd away from PWD - always use git -C "$PWD"
# - Detect main worktree: PWD == git rev-parse --show-toplevel
# - Worktree is isolated: ALL operations allowed inside worktree
# - Dynamic worktree path via git worktree list parent

set -euo pipefail

# Read tool input JSON
input=$(cat)
COMMAND=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

[[ -z "$COMMAND" ]] && exit 0

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
# Helper: Check if command is dangerous (7 rules)
# =====================================================================
is_dangerous_bash() {
  local command="$1"

  # Rule 1: File-writing commands
  if echo "$command" | grep -qE '(\s>>|\s>|\|[[:space:]]*tee\b|\|cat\s*>|sed\s+-i|perl\s+-i|\S\.write\(|truncate|dd\b.*of=|tr\b.*of=)' && \
     ! echo "$command" | grep -qE '[^>]*>(2\s*)?\s*/dev/null'; then
    return 0
  fi

  # Rule 2: git push to main
  if echo "$command" | grep -qE 'git[[:space:]]+push[[:space:]]+[^;]*main|git[[:space:]]+push[[:space:]]+[^;]*refs/heads/main'; then
    return 0
  fi

  # Rule 3: bare --force (without --force-with-lease)
  if echo "$command" | grep -qE 'git[[:space:]]+push[[:space:]]+[^;]*'"--force($| )" && \
     ! echo "$command" | grep -qE -- '--force-with-lease'; then
    return 0
  fi

  # Rule 3b: -f short form
  if echo "$command" | grep -qE 'git[[:space:]]+push[[:space:]]+[^;]*'"-f($| )" && \
     ! echo "$command" | grep -qE -- '--force-with-lease'; then
    return 0
  fi

  # Rule 4: git reset --hard (bare form)
  if echo "$command" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard$'; then
    return 0
  fi

  # Rule 5: git clean -x or -X
  if echo "$command" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[fFxX]([dD]*[xX]+[dD]*)$'; then
    return 0
  fi

  # Rule 6: delete main/master
  if echo "$command" | grep -qE 'git[[:space:]]+branch[[:space:]]+-[Dd][[:space:]]+(main|master)'; then
    return 0
  fi

  return 1
}

# =====================================================================
# Core Logic: Only block on main branch (D1+D2 fix)
# =====================================================================
if ! is_on_main_branch; then
  # Inside a worktree - always allow (worktree is isolated)
  exit 0
fi

# In main worktree - check for dangerous commands
if is_dangerous_bash "$COMMAND"; then
  DENY_REASON="Cannot run dangerous commands in main worktree. Switch to a task worktree first."
  jq -n --arg r "$DENY_REASON" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
fi

exit 0
