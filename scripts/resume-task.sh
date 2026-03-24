#!/usr/bin/env bash
# resume-task.sh — List active worktrees and their status

set -euo pipefail

REPO_DIR=$(git rev-parse --show-toplevel 2>/dev/null || { echo "Not a git repository." >&2; exit 1; })
cd "$REPO_DIR"

echo "=== Active Worktrees ==="
git worktree list --porcelain | while read -r line; do
  if [[ "$line" =~ ^path\  ]]; then
    path="${line#path }"
    echo ""
    echo "  path:    $path"
  elif [[ "$line" =~ ^branch\  ]]; then
    branch="${line#branch }"
    echo "  branch:  $branch"
  elif [[ "$line" =~ ^HEAD\  ]]; then
    head="${line#HEAD }"
    commit=$(git log -1 --format="%h %s" "$head" 2>/dev/null || echo "unknown")
    echo "  HEAD:    $commit"
  fi
done

echo ""
echo "=== Unpushed Task Branches ==="
for branch in $(git branch --list 'task/*' --format='%(refname:short)' 2>/dev/null); do
  ahead=$(git log origin/main.."origin/$branch" --oneline 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  if [[ "$ahead" -gt 0 ]]; then
    echo "  $branch has $ahead unpushed commit(s)"
  fi
done

echo ""
echo "=== Current Context ==="
branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
echo "  current branch: $branch"
echo "  current path:   $PWD"

if git diff --quiet && git diff --cached --quiet; then
  echo "  status: clean"
else
  echo "  status: dirty (uncommitted changes)"
fi
