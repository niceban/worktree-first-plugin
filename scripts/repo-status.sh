#!/usr/bin/env bash
# repo-status.sh — Inject current repo state into session context
# Called on SessionStart hook
# stdout is added to Claude context

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$PROJECT_DIR" ]] && exit 0

cd "$PROJECT_DIR"

# Current branch
branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)

# Clean/dirty
if git diff --quiet && git diff --cached --quiet; then
  status="clean"
else
  status="dirty"
fi

# Determine if inside a worktree (pwd is not repo root)
is_worktree=false
worktree_path=""
if [[ "$PWD" != "$PROJECT_DIR" ]]; then
  is_worktree=true
  worktree_path="$PWD"
fi

# Unpushed commits on current branch
unpushed=$(git log origin/main..HEAD --oneline 2>/dev/null | wc -l | tr -d ' ') || unpushed=0

# Recent commits
recent=$(git log --oneline -3 --format="%h %s" 2>/dev/null | sed 's/^/  /')

# Print to stdout (gets added to Claude context)
cat <<EOF

=== Repo Status ===
branch:     $branch
status:     $status
is_worktree: $is_worktree
${worktree_path:+
worktree:   $worktree_path}
unpushed:   $unpushed commit(s)

Recent commits:
$recent

EOF

# Warn if on main
if [[ "$branch" == "main" ]]; then
  echo "  [WARN] Currently on main. Use /worktree-first:start-task to create a task worktree."
fi

# Warn if dirty
if [[ "$status" == "dirty" ]]; then
  echo "  [WARN] Working tree has uncommitted changes."
fi
