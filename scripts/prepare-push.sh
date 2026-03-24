#!/usr/bin/env bash
# prepare-push.sh — Rebase, enforce clean history, validate before push
# Does NOT auto-push — asks for confirmation
# exit 0 = ready to push, exit 1 = not ready (blocked)

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$PROJECT_DIR" ]] && { echo "Not a git repository." >&2; exit 1; }
cd "$PROJECT_DIR"

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
if ! git rebase origin/main; then
  echo "Rebase failed — resolve conflicts manually, then re-run." >&2
  exit 1
fi
echo "Rebase successful."

echo ""
echo "=== Step 2: Enforce clean history ==="
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
echo "=== Step 3: Validation ==="
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

echo ""
echo "=== Ready to push ==="
echo "Branch: $branch"
echo "Commits to push:"
git log --oneline origin/main..HEAD
echo ""
echo "Run: git push --force-with-lease -u origin $branch"
echo "(This plugin does not auto-push — confirm manually)"
