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
  # Detect file-writing commands: output redirect, tee, sed -i, perl -i,
  # python -c with write, truncate, dd, tr of=
  # Allow: redirects to /dev/null (any spacing: >file, > file, >  file)
  if echo "$COMMAND" | grep -qE '(\s>>|\s>|\|[[:space:]]*tee\b|\|cat\s*>|sed\s+-i|perl\s+-i|\S\.write\(|truncate|dd\b.*of=|tr\b.*of=)' && \
     ! echo "$COMMAND" | grep -qE '[^>]*>(2\s*)?\s*/dev/null'; then
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
# Blocks: --force, -f (both long and short form)
# Allows: --force-with-lease (always safe)
# =====================================================================
if echo "$COMMAND" | grep -qE 'git[[:space:]]+push[[:space:]]+[^;]*'"--force($| )" && \
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

# Also block -f short form (but not -fx, -fX which are different flags)
if echo "$COMMAND" | grep -qE 'git[[:space:]]+push[[:space:]]+[^;]*'"-f($| )" && \
   ! echo "$COMMAND" | grep -qE -- '--force-with-lease'; then
  DENY_REASON="Use --force-with-lease (-f is not allowed). Bare force push is dangerous."
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
# Rule 4: Block git reset --hard without explicit commit/path
# git reset --hard (bare, no target) is maximally dangerous: resets index
# and working tree to HEAD, losing ALL uncommitted changes.
# git reset --hard <commit> is still dangerous but intentional.
# We block only the bare form (no path/ref after --hard).
# =====================================================================
if echo "$COMMAND" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard$'; then
  DENY_REASON="git reset --hard with no target is maximally dangerous. Use git restore or specify a commit."
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
# Rule 5: Block git clean when -x or -X flag is present (destroys
# ignored files like build artifacts, node_modules). -fd without x/X is safe.
# Blocks: -fdx, -fdX, -fdxd, -fdxx, -fx, -fX (any sequence with x/X)
# Pattern: [dD]*[xX]+[dD]* matches x/X surrounded by any number of d/D
# =====================================================================
if echo "$COMMAND" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[fFxX]([dD]*[xX]+[dD]*)$'; then
  DENY_REASON="git clean with -x or -X destroys ignored files (build artifacts, node_modules). Use -fd for safe cleanup."
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

exit 0
