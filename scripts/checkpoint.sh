#!/usr/bin/env bash
# checkpoint.sh — Create a checkpoint commit, then run lightweight validation

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$PROJECT_DIR" ]] && { echo "Not a git repository." >&2; exit 1; }
cd "$PROJECT_DIR"

# Find the current worktree path (correctly identifies current worktree even from within it)
# git rev-parse --show-toplevel always returns the actual working tree root
WORKTREE_PATH="$(git rev-parse --show-toplevel 2>/dev/null || echo '')"

# Derive slug from the worktree path (last path component)
WORKTREE_SLUG="$(basename "$WORKTREE_PATH")"

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

  # Call LLM to analyze the diff (use --mode write to get structured JSON output)
  # Cross-platform timeout: use perl (available on both Linux and macOS)
  local ccw_output
  ccw_output=$(perl -e 'alarm shift; exec @ARGV' 30 -- ccw cli -p "PURPOSE: Analyze staged git diff and recommend whether to commit. Return ONLY valid JSON.
TASK: Review the diff content. Evaluate if changes are meaningful and complete.
EXPECTED: JSON with fields: judgment (must be exactly \"值得 commit\" or \"不值得 commit\"), reason (1-2 sentence explanation), suggested_message (brief commit message, 5-10 words max)
CONSTRAINTS: Output ONLY valid JSON, no markdown code blocks, no explanation, just the JSON object
---
diff:
${diff_content}" --tool gemini --mode write 2>/dev/null) || true

  # Parse LLM response using jq (fall back to grep if jq unavailable)
  # Returns: 0 + stdout = success (judgment, reason, suggested_msg set)
  #          1 = failure (LLM unavailable or parse failed)
  if [[ -n "$ccw_output" ]]; then
    local judgment reason suggested_msg
    if command -v jq &>/dev/null; then
      judgment=$(echo "$ccw_output" | jq -r '.judgment // empty' 2>/dev/null || echo "")
      reason=$(echo "$ccw_output" | jq -r '.reason // empty' 2>/dev/null || echo "")
      suggested_msg=$(echo "$ccw_output" | jq -r '.suggested_message // empty' 2>/dev/null || echo "")
    else
      # Strip markdown code blocks if present, then grep fields
      local json_text
      json_text=$(echo "$ccw_output" | sed 's/```json//g;s/```//g' | tr -d '\n')
      judgment=$(echo "$json_text" | grep -oP '"judgment"[[:space:]]*:[[:space:]]*"\K[^"]+' || echo "")
      reason=$(echo "$json_text" | grep -oP '"reason"[[:space:]]*:[[:space:]]*"\K[^"]+' || echo "")
      suggested_msg=$(echo "$json_text" | grep -oP '"suggested_message"[[:space:]]*:[[:space:]]*"\K[^"]+' || echo "")
    fi

    if [[ -n "$judgment" && -n "$reason" ]]; then
      # Output recommendation for user to see
      advisor_output="AI Advisor Recommendation:"
      advisor_output+="\n  Judgment: $judgment"
      advisor_output+="\n  Reason: $reason"
      if [[ -n "$suggested_msg" ]]; then
        advisor_output+="\n  Suggested message: checkpoint: $suggested_msg"
      fi
      echo -e "$advisor_output"
      # Return suggestion_msg as stdout so caller can use it
      [[ -n "$suggested_msg" ]] && echo "SUGGESTION: checkpoint: $suggested_msg"
      return 0
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
    if [[ "$line" =~ ^new\ file ]]; then
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
  # Capture AI advisor output to temp file (clean separation of stdout from suggestion)
  local ai_out_file
  ai_out_file=$(mktemp)
  local ai_suggestion=""
  if _ai_advisor > "$ai_out_file" 2>&1; then
    # AI succeeded: extract suggested_message from output
    ai_suggestion=$(grep '^SUGGESTION:' "$ai_out_file" | sed 's/^SUGGESTION: //')
    # Show AI recommendation
    cat "$ai_out_file"
    # Also show rule-based as alternative
    local rule_suggestion
    rule_suggestion=$(_generate_suggestion)
    echo ""
    echo "Rule-based alternative: checkpoint: $rule_suggestion"
  else
    # AI failed: show output and fall back to rule-based
    cat "$ai_out_file"
    ai_suggestion=$(_generate_suggestion)
    echo "Suggested: checkpoint: $ai_suggestion"
  fi
  rm -f "$ai_out_file"
  echo ""
  echo "Press Enter to accept, or type your own:"
  read -r USER_MSG
  if [[ -z "$USER_MSG" ]]; then
    MSG="$ai_suggestion"
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
