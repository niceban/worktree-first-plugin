#!/usr/bin/env bash
# guard-auto-worktree.sh — Auto-create worktree when blocking dangerous operations on main
# Called on PreToolUse (Edit|Write|MultiEdit|Bash)
# stdin: tool input JSON
# exit 0 + JSON = deny (blocking)
# exit 0 without JSON = allow
#
# ARCHITECTURE (D1+D2+D3+D4+D5+D6+D7):
# - NEVER cd away from PWD - always use git -C "$PWD"
# - Main worktree detection: PWD == git rev-parse --show-toplevel
# - In task worktree: ALWAYS ALLOW (worktree is isolated)
# - auto-create with idempotency (D5) and rollback (D6)
# - Dynamic worktree path via git worktree list parent (D7)

set -euo pipefail

# Read tool input JSON
input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

# =====================================================================
# Helper: Get git root — use CLAUDE_PROJECT_DIR if PWD reset to main
# =====================================================================
get_git_root() {
  local git_root
  git_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "")
  if [[ -z "$git_root" ]] && [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    git_root=$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "")
  fi
  echo "$git_root"
}

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
# Helper: Get dynamic worktree base path (D7 fix)
# =====================================================================
get_wt_base() {
  local git_root
  git_root=$(get_git_root)
  if [[ -z "$git_root" ]]; then
    echo "../wt"
    return
  fi
  echo "$(dirname "$git_root")/wt"
}

# =====================================================================
# Helper: Generate unique slug for worktree (D5 idempotency)
# =====================================================================
generate_slug() {
  local op_type="$1"
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  echo "${op_type}-${timestamp}"
}

# =====================================================================
# Helper: Create worktree with rollback on failure (D6 fix)
# =====================================================================
auto_create_worktree() {
  local slug="$1"
  local branch_name="task/${slug}"
  local wt_base
  wt_base=$(get_wt_base)
  local wt_path="${wt_base}/${slug}"
  local created=false

  # Idempotency check (D5 fix)
  if [[ -d "$wt_path" ]]; then
    echo "Worktree already exists at $wt_path" >&2
    return 1
  fi

  # Create worktree — show errors, verify directory was created
  local wt_add_output
  wt_add_output=$(git worktree add -b "$branch_name" "$wt_path" origin/main 2>&1)
  local wt_add_status=$?
  if [[ $wt_add_status -ne 0 ]]; then
    echo "Failed to create worktree at $wt_path: $wt_add_output" >&2
    return 1
  fi

  # Verify worktree directory was actually created
  if [[ ! -d "$wt_path" ]]; then
    echo "Worktree directory not created at $wt_path" >&2
    return 1
  fi
  created=true

  # Configure the worktree
  git -C "$wt_path" config --worktree rerere.enabled true 2>/dev/null || true
  git -C "$wt_path" config --worktree branch.autosetuprebase always 2>/dev/null || true

  # Create metadata (D6: rollback on failure)
  local git_root
  git_root=$(get_git_root)
  local meta_dir="${git_root}/.worktree-first/worktrees"
  if ! mkdir -p "$meta_dir"; then
    echo "Failed to create metadata directory" >&2
    [[ "$created" == "true" ]] && git worktree remove "$wt_path"
    return 1
  fi

  # Write metadata with verified success
  local meta_file="${meta_dir}/${slug}.json"
  local meta_content
  meta_content=$(cat <<EOF
{
  "slug": "${slug}",
  "branch": "${branch_name}",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_active_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "dirty": false,
  "checkpoints": []
}
EOF
)
  if ! echo "$meta_content" > "$meta_file"; then
    echo "Failed to write metadata file" >&2
    [[ "$created" == "true" ]] && git worktree remove "$wt_path"
    return 1
  fi

  # Double-verify metadata file exists
  if [[ ! -f "$meta_file" ]]; then
    echo "Metadata file not created at $meta_file" >&2
    [[ "$created" == "true" ]] && git worktree remove "$wt_path"
    return 1
  fi

  echo "auto-worktree: Created worktree at $wt_path" >&2
  echo "$slug"
  return 0
}

# =====================================================================
# Helper: Check if tool is a write operation
# =====================================================================
is_write_operation() {
  local t="$1"
  [[ "$t" == "Edit" ]] || [[ "$t" == "Write" ]] || [[ "$t" == "MultiEdit" ]]
}

# =====================================================================
# Helper: Check if command is dangerous (7 rules, D3)
# =====================================================================
is_dangerous_bash() {
  local cmd="$1"

  # Rule 1: File-writing commands
  if echo "$cmd" | grep -qE '(\s>>|\s>|\|[[:space:]]*tee\b|\|cat\s*>|sed\s+-i|perl\s+-i|\S\.write\(|truncate|dd\b.*of=|tr\b.*of=)' && \
     ! echo "$cmd" | grep -qE '[^>]*>(2\s*)?\s*/dev/null'; then
    return 0
  fi

  # Rule 2: git push to main
  if echo "$cmd" | grep -qE 'git[[:space:]]+push[[:space:]]+[^;]*main|git[[:space:]]+push[[:space:]]+[^;]*refs/heads/main'; then
    return 0
  fi

  # Rule 3: bare --force
  if echo "$cmd" | grep -qE 'git[[:space:]]+push[[:space:]]+[^;]*'"--force($| )" && \
     ! echo "$cmd" | grep -qE -- '--force-with-lease'; then
    return 0
  fi

  # Rule 3b: -f short form
  if echo "$cmd" | grep -qE 'git[[:space:]]+push[[:space:]]+[^;]*'"-f($| )" && \
     ! echo "$cmd" | grep -qE -- '--force-with-lease'; then
    return 0
  fi

  # Rule 4: git reset --hard (bare form)
  if echo "$cmd" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard$'; then
    return 0
  fi

  # Rule 5: git clean -x or -X
  if echo "$cmd" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[fFxX]([dD]*[xX]+[dD]*)$'; then
    return 0
  fi

  # Rule 6: delete main/master
  if echo "$cmd" | grep -qE 'git[[:space:]]+branch[[:space:]]+-[Dd][[:space:]]+(main|master)'; then
    return 0
  fi

  # Rule 7: git worktree remove (non-force) — should use finish-task instead
  if echo "$cmd" | grep -qE 'git[[:space:]]+worktree[[:space:]]+remove[[:space:]]+' && \
     ! echo "$cmd" | grep -qE '--force'; then
    return 0
  fi

  return 1
}

# =====================================================================
# CORE LOGIC (D1+D2+D3)
# =====================================================================

# If not on main branch, allow everything (task worktree is isolated)
if ! is_on_main_branch; then
  exit 0
fi

# In main worktree: check for dangerous operations
# Rule: Edit/Write/MultiEdit -> auto-create worktree
if is_write_operation "$tool_name"; then
  slug=$(generate_slug "edit")
  if auto_create_worktree "$slug"; then
    wt_base=$(get_wt_base)
    jq -n --arg slug "$slug" --arg wt_path "${wt_base}/${slug}" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("Auto-created worktree at " + $wt_path + ". Switch to it with: cd " + $wt_path + ", then retry your edit."),
        suggestions: [
          {
            "description": "Switch to worktree and continue",
            "action": "bash",
            "command": ("cd " + $wt_path + " && echo \"Switched to worktree. You can now edit files.\"")
          }
        ]
      }
    }'
    exit 0
  fi
fi

# Rule: Dangerous Bash command -> auto-create worktree
if [[ -n "$command" ]] && is_dangerous_bash "$command"; then
  slug=$(generate_slug "bash")
  if auto_create_worktree "$slug"; then
    wt_base=$(get_wt_base)
    jq -n --arg slug "$slug" --arg wt_path "${wt_base}/${slug}" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("Auto-created worktree at " + $wt_path + ". Switch to it with: cd " + $wt_path + ", then retry your command."),
        suggestions: [
          {
            "description": "Switch to worktree and continue",
            "action": "bash",
            "command": ("cd " + $wt_path + " && echo \"Switched to worktree. You can now run commands.\"")
          }
        ]
      }
    }'
    exit 0
  fi
fi

# In main worktree but not dangerous -> block anyway (main worktree is protected)
if is_write_operation "$tool_name" || is_dangerous_bash "$command"; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Cannot perform this operation in main worktree. Use /worktree-first:start-task to create a task worktree."
    }
  }'
  exit 0
fi

exit 0
