#!/usr/bin/env bash
# checkpoint.sh — Create a checkpoint commit, then run lightweight validation

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$PROJECT_DIR" ]] && { echo "Not a git repository." >&2; exit 1; }
cd "$PROJECT_DIR"

# Find the worktree path (used for metadata lookup)
# When in a worktree, git worktree list shows the worktree; from main repo, shows main
WORKTREE_PATH="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"

# Guard: must not be on main
branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [[ "$branch" == "main" ]]; then
  echo "BLOCKED: Cannot checkpoint on main branch." >&2
  exit 1
fi

# Guard: must have staged changes
if git diff --cached --quiet 2>/dev/null; then
  echo "Nothing staged. Run 'git add -p <file>' or 'git add <file>' first." >&2
  exit 1
fi

# AI Checkpoint Advisor: Analyze staged diff and provide commit recommendation
_ai_advisor() {
  local diff_content=""
  local advisor_output=""

  # Get staged diff content
  diff_content=$(git diff --cached 2>/dev/null || echo "")
  if [[ -z "$diff_content" ]]; then
    echo "AI Advisor: No staged changes to analyze."
    return 1
  fi

  # Call LLM to analyze the diff
  local ccw_output
  ccw_output=$(ccw cli -p "PURPOSE: Analyze staged git diff and recommend whether to commit.
TASK: • Review the diff content • Evaluate if changes are meaningful and complete • Provide a clear recommendation
MODE: analysis
CONTEXT: (diff content below)
EXPECTED: JSON output with: {judgment: \"值得 commit\" or \"不值得 commit\", reason: \"1-2 sentence explanation\", suggested_message: \"brief commit message suggestion\"}
CONSTRAINTS: Output must be valid JSON only, no markdown formatting
---
diff:
${diff_content}" --tool gemini --mode analysis 2>/dev/null) || true

  # Parse LLM response
  if [[ -n "$ccw_output" ]]; then
    # Extract JSON from response (handle potential markdown code blocks)
    local json_response
    json_response=$(echo "$ccw_output" | sed -n '/{/,/}/p' | head -20)
    if [[ -n "$json_response" ]]; then
      local judgment reason suggested_msg
      judgment=$(echo "$json_response" | grep -oP '"judgment"[[:space:]]*:[[:space:]]*"\K[^"]+' || echo "")
      reason=$(echo "$json_response" | grep -oP '"reason"[[:space:]]*:[[:space:]]*"\K[^"]+' || echo "")
      suggested_msg=$(echo "$json_response" | grep -oP '"suggested_message"[[:space:]]*:[[:space:]]*"\K[^"]+' || echo "")

      if [[ -n "$judgment" && -n "$reason" ]]; then
        advisor_output="AI Advisor Recommendation:"
        advisor_output+="\n  Judgment: $judgment"
        advisor_output+="\n  Reason: $reason"
        if [[ -n "$suggested_msg" ]]; then
          advisor_output+="\n  Suggested message: $suggested_msg"
        fi
        echo -e "$advisor_output"
        return 0
      fi
    fi
  fi

  echo "AI Advisor: LLM analysis unavailable, using rule-based suggestion."
  return 1
}

# Generate suggested commit message from staged changes (rule-based fallback)
_generate_suggestion() {
  local suggestion=""
  local changes=""

  # Get list of changed files with status
  while IFS= read -r line; do
    # Parse "status count filename" from --stat output
    # e.g., "1 file changed, 2 insertions(+), 3 deletions(-)" or "src/foo.py"
    if [[ "$line" =~ ^[[:space:]]*([0-9]+)\ file ]]; then
      continue  # skip summary line
    fi
    # Check for new/deleted/modified file indicators
    if [[ "$line" =~ ^(new file|"") ]]; then
      changes+="add "
    elif [[ "$line" =~ ^deleted ]]; then
      changes+="remove "
    elif [[ -n "$line" ]]; then
      changes+="fix "
    fi
  done < <(git diff --cached --stat)

  # Extract meaningful prefixes from filenames
  local prefixes=""
  while IFS= read -r file; do
    # Get base name without extension
    local base
    base=$(basename "$file" | sed 's/\.[^.]*$//')
    # Take first meaningful word (camelCase or snake_case split)
    if [[ "$base" =~ ^[a-z]+_[a-z]+$ ]]; then
      # snake_case
      base=$(echo "$base" | cut -d'_' -f1)
    elif [[ "$base" =~ ^[a-z]+[A-Z] ]]; then
      # camelCase - take prefix before first capital
      base=$(echo "$base" | sed 's/\([a-z]\+\).*/\1/')
    fi
    [[ -n "$base" && "$base" != "$file" ]] && prefixes+="$base "
  done < <(git diff --cached --name-only)

  # Build suggestion
  if [[ -n "$changes" ]]; then
    suggestion="${changes}${prefixes:-changes}"
  else
    suggestion="checkpoint"
  fi

  echo "$suggestion"
}

# Get commit message
MSG="${1:-}"
if [[ -z "$MSG" ]]; then
  echo ""
  echo "=== AI Checkpoint Advisor ==="
  if _ai_advisor; then
    # AI provided recommendation, use it as suggestion
    SUGGESTION=$(_generate_suggestion)
    echo "Rule-based suggestion: checkpoint: $SUGGESTION"
  else
    # Fallback to rule-based
    SUGGESTION=$(_generate_suggestion)
    echo "Suggested: checkpoint: $SUGGESTION"
  fi
  echo "Press Enter to accept, or type your own:"
  read -r USER_MSG
  if [[ -z "$USER_MSG" ]]; then
    MSG="$SUGGESTION"
  else
    MSG="$USER_MSG"
  fi
fi
[[ -z "$MSG" ]] && { echo "Empty message. Aborted." >&2; exit 1; }

# Commit
git commit -m "checkpoint: $MSG"
echo "Checkpoint created: $(git log -1 --format="%h $MSG")"

# Lightweight validation after commit
echo ""
echo "=== Validation ==="

validated=true

if command -v make &>/dev/null; then
  if make format &>/dev/null; then
    echo "  [OK] format passed"
  fi
  if make lint &>/dev/null; then
    echo "  [OK] lint passed"
  elif command -v eslint &>/dev/null && [[ -n "$(git diff --name-only | grep -E '\.(js|ts|jsx|tsx)$')" ]]; then
    git diff --name-only | grep -E '\.(js|ts|jsx|tsx)$' | xargs eslint --max-warnings=0 2>/dev/null && echo "  [OK] eslint passed"
  fi
  if make test-quick &>/dev/null || make test &>/dev/null; then
    echo "  [OK] quick tests passed"
  fi
fi

# Update metadata: add checkpoint, set dirty=false, update timestamps
_meta_update_checkpoint() {
  # slug is the worktree directory name
  local slug
  slug=$(basename "$WORKTREE_PATH")
  # Metadata is at {repo_root}/.worktree-first/worktrees/{slug}.json
  # From a worktree, git rev-parse --git-dir returns the main repo's .git path
  local repo_root
  repo_root="$(git rev-parse --git-dir)/.."
  local meta_file="${repo_root}/.worktree-first/worktrees/${slug}.json"
  if [[ -f "$meta_file" ]]; then
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    # Use jq to update metadata fields atomically
    jq \
      --arg msg "$MSG" \
      --arg now "$now" \
      '
        .checkpoints += [$msg] |
        .last_checkpoint_message = $msg |
        .last_active_at = $now |
        .dirty = false
      ' "$meta_file" > "${meta_file}.tmp" && mv "${meta_file}.tmp" "$meta_file"
    echo "  [OK] metadata updated"
  fi
}
_meta_update_checkpoint

# Syntax check modified files (not staged — committed files)
for file in $(git diff --name-only HEAD~1..HEAD 2>/dev/null); do
  case "$file" in
    *.sh)
      bash -n "$file" 2>/dev/null || { echo "  [FAIL] syntax error in $file"; validated=false; }
      ;;
    *.js|*.mjs)
      node --check "$file" 2>/dev/null || { echo "  [FAIL] syntax error in $file"; validated=false; }
      ;;
    *.py)
      python3 -m py_compile "$file" 2>/dev/null || { echo "  [FAIL] syntax error in $file"; validated=false; }
      ;;
  esac
done

[[ "$validated" == "true" ]] && echo "  [OK] all checks passed"

echo ""
echo "Recent commits:"
git log --oneline -3 --format="  %h %s"
