#!/usr/bin/env bash
# start-task.sh — Create a new task branch + worktree from origin/main
# Usage: start-task.sh <type> <slug>

set -euo pipefail

TYPE="${1:-}"
SLUG="${2:-}"

if [[ -z "$TYPE" ]] || [[ -z "$SLUG" ]]; then
  echo "Usage: start-task.sh <type> <slug>" >&2
  echo "  type: feat|fix|refactor|spike|chore" >&2
  echo "  slug: short-name (kebab-case)" >&2
  exit 1
fi

case "$TYPE" in
  feat|fix|refactor|spike|chore|auto) ;;
  *)
    echo "Invalid type: $TYPE. Use feat|fix|refactor|spike|chore|auto" >&2
    exit 1
    ;;
esac

REPO_DIR=$(git rev-parse --show-toplevel)
BRANCH_NAME="task/${TYPE}-${SLUG}"
WT_PATH="../wt/${SLUG}"
WT_DIR="${REPO_DIR}/.worktree-first/worktrees"
WT_META="${WT_DIR}/${SLUG}.json"

cd "$REPO_DIR"

# Idempotency: if worktree already exists, exit 0 with message
if [[ -d "$WT_PATH" ]]; then
  echo "already exists"
  exit 0
fi

# Ensure metadata directory exists
mkdir -p "$WT_DIR"

# Check: must be in a git repo
git rev-parse --git-dir &>/dev/null || { echo "Not a git repository." >&2; exit 1; }

# Check: origin/main must exist
git rev-parse --verify origin/main &>/dev/null || { echo "No origin/main found. Check remote configuration." >&2; exit 1; }

# Check: no uncommitted changes on main before switching
git switch main && git fetch origin && git pull --ff-only

# Check: branch doesn't already exist (idempotent: worktree might exist from previous run)
if git rev-parse --verify "$BRANCH_NAME" &>/dev/null; then
  if [[ -d "$WT_PATH" ]]; then
    echo "already exists"
    exit 0
  fi
  echo "Branch $BRANCH_NAME already exists but worktree missing. Use resume-task to fix." >&2
  exit 1
fi

# Check: worktree path doesn't already exist (already handled above by idempotency check)
if [[ -d "$WT_PATH" ]]; then
  echo "already exists"
  exit 0
fi

# CRITICAL: enable extensions.worktreeConfig BEFORE creating worktree
# Without this, --worktree config writes to .git/config instead of per-worktree config.worktree
git config extensions.worktreeConfig true

# Create branch + worktree
git worktree add -b "$BRANCH_NAME" "$WT_PATH" origin/main

# Configure worktree (now safe to use --worktree since extension is enabled)
git -C "$WT_PATH" config --worktree rerere.enabled true
git -C "$WT_PATH" config --worktree branch.autosetuprebase always
git -C "$WT_PATH" config --worktree user.name "Claude Worker"

# Write worktree metadata (with backup)
_meta_backup() {
  [[ -f "$WT_META" ]] || return 0
  local backup_dir="${WT_META}.backups"
  mkdir -p "$backup_dir"
  cp "$WT_META" "${backup_dir}/$(date -u +%Y%m%d-%H%M%S).json"
  # Keep only 3 most recent backups
  ls -1t "$backup_dir" | tail -n +4 | xargs -r rm -f
}
_meta_backup
cat > "$WT_META" <<EOF
{
  "slug": "$SLUG",
  "branch": "$BRANCH_NAME",
  "worktree": "$(realpath "$WT_PATH")",
  "status": "active",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_active_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "dirty": false,
  "checkpoints": [],
  "last_checkpoint_message": null,
  "pr_url": null
}
EOF

echo "Created: branch=$BRANCH_NAME worktree=$(realpath "$WT_PATH")"
echo "Next: cd $WT_PATH && claude"
