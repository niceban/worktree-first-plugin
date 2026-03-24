#!/usr/bin/env bash
# prepare-push.sh — Rebase, enforce clean history, validate before push
# Does NOT auto-push — asks for confirmation
# exit 0 = ready to push, exit 1 = not ready (blocked)

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$PROJECT_DIR" ]] && { echo "Not a git repository." >&2; exit 1; }
cd "$PROJECT_DIR"

# Find the current worktree path (correctly identifies current worktree even from within it)
WORKTREE_PATH="$(git rev-parse --show-toplevel 2>/dev/null || echo '')"

# Derive slug from the worktree path (last path component)
WORKTREE_SLUG="$(basename "$WORKTREE_PATH")"

branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

# Guard: must not be on main
if [[ "$branch" == "main" ]]; then
  echo "BLOCKED: Cannot prepare-push from main." >&2
  exit 1
fi

# Guard: must have commits
if ! git log --oneline origin/main..HEAD &>/dev/null; then
  echo "BLOCKED: No commits to push." >&2
  exit 1
fi

echo "=== Step 1: Fetch and rebase onto latest main ==="
git fetch origin
PRE_REBASE_REF=$(git rev-parse HEAD)
if ! git rebase origin/main; then
  git rebase --abort
  echo "Rebase failed. Your changes are intact."
  echo "Run 'git rebase --abort' if not already done, fix conflicts, then re-run /worktree-first:prepare-push" >&2
  exit 1
fi
echo "  ✓ Rebase successful"

echo ""
echo "=== Step 2: Enforce clean history ==="
echo "  Checking commit count..."
commit_count=$(git log --oneline origin/main..HEAD | wc -l | tr -d ' ')
echo "Commits on branch: $commit_count"

if [[ "$commit_count" -gt 1 ]]; then
  # Enforce: squash required for >1 commit
  echo ""
  echo "BLOCKED: $commit_count commits detected. Squash to 1 review commit required."
  echo "Run: git rebase -i origin/main"
  echo "  - Mark all except first as 'squash' or 'fixup'"
  echo "  - Write a clean commit message: <type>: <intent>"
  echo ""
  echo "After squashing, re-run: /worktree-first:prepare-push"
  exit 1
fi

# After squash check: verify only 1 commit remains
final_count=$(git log --oneline origin/main..HEAD | wc -l | tr -d ' ')
if [[ "$final_count" -gt 1 ]]; then
  echo "BLOCKED: Still $final_count commits after rebase. Squash again." >&2
  exit 1
fi

echo "History is clean: 1 review commit."

echo ""
echo "=== Step 3: AI Push Readiness Assessment ==="

# Gather context for AI assessment
_ai_assessment() {
  local diff_stats
  local changed_files
  local commit_msg
  local checkpoint_history
  local diff_content

  # Diff statistics
  diff_stats=$(git diff --stat origin/main..HEAD 2>/dev/null | tail -1)
  if [[ -z "$diff_stats" ]]; then
    diff_stats="No diff available"
  fi

  # Changed file list
  changed_files=$(git diff --name-only origin/main..HEAD 2>/dev/null | head -20)
  if [[ -z "$changed_files" ]]; then
    changed_files="None"
  fi

  # Commit message
  commit_msg=$(git log -1 --format="%B" origin/main..HEAD 2>/dev/null | head -5)
  if [[ -z "$commit_msg" ]]; then
    commit_msg="No commit message"
  fi

  # Checkpoint history from metadata (if available)
  local slug
  slug=$(basename "$WORKTREE_PATH")
  local repo_root
  repo_root="$(git rev-parse --git-dir)/.."
  local meta_file="${repo_root}/.worktree-first/worktrees/${slug}.json"
  if [[ -f "$meta_file" ]]; then
    checkpoint_history=$(jq -r '.checkpoints[-5:] | reverse | join(" | ")' "$meta_file" 2>/dev/null || echo "unavailable")
  else
    checkpoint_history="unavailable"
  fi

  # Diff content for analysis (first 80 lines)
  diff_content=$(git diff origin/main..HEAD 2>/dev/null | head -80)

  # Build the assessment prompt
  local prompt
  prompt="PURPOSE: Assess PR push readiness and give 1-5 star rating with actionable feedback
TASK: Analyze the following branch context and rate push readiness from 1-5 stars
ANALYSIS DIMENSIONS:
  - Diff size: small focused changes score better than large sprawling ones
  - File count: fewer, focused files score better than many unrelated files
  - Commit message quality: clear, conventional commits score better
  - Change purpose: identifiable feature/fix is better than unclear mixed changes
  - Test coverage: changes with tests score better

CONTEXT:
=== Diff Stats ===
$diff_stats

=== Changed Files ===
$changed_files

=== Commit Message ===
$commit_msg

=== Recent Checkpoints (from metadata) ===
$checkpoint_history

=== Diff Preview (first 80 lines) ===
$diff_content

EXPECTED OUTPUT FORMAT:
Start with: STAR_RATING: X/5
Then provide:
  - Rating: X stars
  - Summary: 1-2 sentence overall assessment
  - Strengths: what looks good about this change
  - Concerns: what might need attention
  - Suggestions: specific improvements if rating < 4 stars
  - Verdict: READY or NEEDS_WORK

CONSTRAINTS: Be honest but constructive. Focus on actionable feedback.
MODE: analysis"

  # Call LLM for assessment
  local assessment
  if command -v ccw &>/dev/null; then
    # Set timeout for CLI call (30 seconds)
    assessment=$(timeout 30 ccw cli -p "$prompt" --tool gemini --mode analysis 2>&1) || {
      local exit_code=$?
      if [[ $exit_code -eq 124 ]]; then
        echo "  [SKIP] AI assessment timed out, continuing..."
      else
        echo "  [SKIP] AI assessment failed (ccw error), continuing without it..."
      fi
      return 0
    }

    if [[ -z "$assessment" ]]; then
      echo "  [SKIP] AI assessment returned empty, continuing..."
      return 0
    fi

    # Parse and display the star rating
    echo ""
    if [[ "$assessment" =~ STAR_RATING:\ ([0-5])/5 ]]; then
      local stars="${BASH_REMATCH[1]}"
      echo "=== AI Push Readiness: $stars/5 stars ==="
      echo ""
      # Extract and display sections
      echo "$assessment" | sed -n '/STAR_RATING:/,$p' | head -30
    else
      # Fallback: just show the raw assessment
      echo "=== AI Assessment ==="
      echo "$assessment" | head -30
    fi
  else
    echo "  [SKIP] ccw CLI not found, skipping AI assessment..."
  fi

  echo ""
}

_ai_assessment

echo ""
echo "=== Step 4: Validation ==="

# Set dirty=false before validation (metadata update)
_meta_set_clean() {
  local slug
  slug=$(basename "$WORKTREE_PATH")
  local repo_root
  repo_root="$(git rev-parse --git-dir)/.."
  local meta_file="${repo_root}/.worktree-first/worktrees/${slug}.json"
  if [[ -f "$meta_file" ]]; then
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq \
      --arg now "$now" \
      '
        .last_active_at = $now |
        .dirty = false
      ' "$meta_file" > "${meta_file}.tmp" && mv "${meta_file}.tmp" "$meta_file"
    echo "  [OK] dirty flag cleared"
  fi
}
_meta_set_clean

validate_pass=true

# Run whatever validation the project has
if command -v make &>/dev/null; then
  if make test-all &>/dev/null || make ci &>/dev/null; then
    echo "  [OK] tests passed"
  else
    echo "  [FAIL] tests failed"
    validate_pass=false
  fi
fi

if command -v go &>/dev/null && [[ -n "$(git diff --name-only | grep '\.go$')" ]]; then
  if go build ./... 2>/dev/null; then
    echo "  [OK] build passed"
  else
    echo "  [FAIL] build failed"
    validate_pass=false
  fi
fi

if [[ "$validate_pass" == "false" ]]; then
  echo ""
  echo "BLOCKED: Validation failed. Fix issues before pushing." >&2
  exit 1
fi

echo "  ✓ Validation passed"

echo ""
echo "=== Ready to push ==="
echo "Branch: $branch"
echo "Commits to push:"
git log --oneline origin/main..HEAD
echo ""
echo "Run: git push --force-with-lease -u origin $branch"
echo "(This plugin does not auto-push — confirm manually)"
