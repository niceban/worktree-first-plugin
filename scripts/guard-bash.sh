#!/usr/bin/env bash
# guard-bash.sh — Block dangerous Bash commands
# Called on PreToolUse (Bash)
# stdin: tool input JSON
# exit 0 + JSON deny = blocked; exit 0 (no JSON) = allowed

set -euo pipefail

# Read tool input JSON
input=$(cat)
COMMAND=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

[[ -z "$COMMAND" ]] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$PROJECT_DIR" ]] && exit 0

# Check current branch
cd "$PROJECT_DIR"
current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

# =====================================================================
# Rule 1: On main branch — block ALL file-writing Bash commands
# =====================================================================
if [[ "$current_branch" == "main" ]]; then
  # Detect file-writing commands using simpler, clear patterns
  # Block: >file, >>file, |tee, |cat>, sed -i, python -c with write, perl -i, truncate, etc.
  # Allow: |less, |grep, |head, read-only redirects to /dev/null
  if echo "$COMMAND" | grep -qE '(\s>>|\s>|\|[[:space:]]*tee\b|\|cat\s*>|sed\s+-i|perl\s+-i|\.write\(|\.truncate|truncate\(|\bdd\b.*of=|\btr\b.*of=)' && \
     ! echo "$COMMAND" | grep -qE '>/dev/null|2\s*>\s*/dev/null'; then
    DENY_REASON="Cannot run file-writing commands while on main branch. Switch to a task worktree first."
    jq -n --arg r "$DENY_REASON" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
    exit 0
  fi
fi

# =====================================================================
# Rule 2: Block git push to main (any form, force or not)
# Blocks: git push origin main, git push origin feature:refs/heads/main, etc.
# =====================================================================
if echo "$COMMAND" | grep -qE 'git[[:space:]]+push[[:space:]]+[^;]*main|git[[:space:]]+push[[:space:]]+[^;]*refs/heads/main'; then
  DENY_REASON="Cannot push directly to main. Use PR + merge workflow to update main."
  jq -n --arg r "$DENY_REASON" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
fi

# =====================================================================
# Rule 3: Block bare --force (without --force-with-lease)
# =====================================================================
if echo "$COMMAND" | grep -qE 'git[[:space:]]+push[[:space:]]+[^;]*--force' && \
   ! echo "$COMMAND" | grep -qE -- '--force-with-lease'; then
  DENY_REASON="Use --force-with-lease instead of bare --force."
  jq -n --arg r "$DENY_REASON" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
fi

# =====================================================================
# Rule 4: Block git reset --hard
# =====================================================================
if echo "$COMMAND" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard'; then
  DENY_REASON="git reset --hard is blocked. Use git restore to selectively undo changes."
  jq -n --arg r "$DENY_REASON" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
fi

# =====================================================================
# Rule 5: Block git clean -fdx (destroy untracked)
# =====================================================================
if echo "$COMMAND" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[fFxX]([xX]|[dD][xX])$'; then
  DENY_REASON="git clean -fdx destroys untracked files. Use -fd for safer cleanup."
  jq -n --arg r "$DENY_REASON" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
fi

# =====================================================================
# Rule 6: Block deleting main or master
# =====================================================================
if echo "$COMMAND" | grep -qE 'git[[:space:]]+branch[[:space:]]+-[Dd][[:space:]]+(main|master)'; then
  DENY_REASON="Cannot delete main or master branch."
  jq -n --arg r "$DENY_REASON" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
fi

# =====================================================================
# Rule 7: On main branch — block all git commands that modify history
# (force push already handled above, this catches non-force push to main separately)
# =====================================================================
# Already handled in Rule 2 above

exit 0
