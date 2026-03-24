#!/usr/bin/env bash
# finish-task.sh — Clean up worktree, local branch, remote branch after merge/abandon

set -euo pipefail

REPO_DIR=$(git rev-parse --show-toplevel 2>/dev/null || { echo "Not a git repository." >&2; exit 1; })
WT_PATH="$PWD"
cd "$REPO_DIR"

branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

# Guard: must be in a worktree (not main, not bare repo root)
if [[ "$branch" == "main" ]]; then
  echo "finish-task can only be run from inside a task worktree." >&2
  exit 1
fi

if [[ "$PWD" == "$REPO_DIR" ]]; then
  echo "finish-task must be run from inside a worktree directory." >&2
  exit 1
fi

# Guard: must be clean
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Worktree has uncommitted changes. Commit, stash, or discard first." >&2
  echo "Run 'git status' to see changes." >&2
  exit 1
fi

merged="${1:-merged}"  # merged | abandoned

# Determine worktree name from path
# ../wt/search-index → search-index
WT_NAME=$(basename "$WT_PATH")

echo "Cleaning up task: $branch"
echo "  worktree: $WT_PATH"
echo "  branch:   $branch"
echo "  mode:     $merged"

# 1. Remove worktree
git worktree remove "$WT_PATH" && echo "  [OK] worktree removed" || echo "  [FAIL] worktree remove failed"

# 2. Delete local branch
if [[ "$merged" == "merged" ]]; then
  git branch -d "$branch" && echo "  [OK] local branch deleted" || echo "  [WARN] branch delete failed (not merged?)"
else
  git branch -D "$branch" && echo "  [OK] local branch force-deleted" || echo "  [WARN] branch delete failed"
fi

# 3. Delete remote branch
if git rev-parse --verify "origin/${branch}" &>/dev/null; then
  git push origin --delete "$branch" && echo "  [OK] remote branch deleted" || echo "  [WARN] remote delete failed (already deleted?)"
else
  echo "  [SKIP] remote branch does not exist"
fi

echo ""
echo "Cleanup complete."
git worktree list --porcelain
