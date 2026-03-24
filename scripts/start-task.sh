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
  feat|fix|refactor|spike|chore) ;;
  *)
    echo "Invalid type: $TYPE. Use feat|fix|refactor|spike|chore" >&2
    exit 1
    ;;
esac

REPO_DIR=$(git rev-parse --show-toplevel)
BRANCH_NAME="task/${TYPE}-${SLUG}"
WT_PATH="../wt/${SLUG}"

cd "$REPO_DIR"

# Check: must be in a git repo
git rev-parse --git-dir &>/dev/null || { echo "Not a git repository." >&2; exit 1; }

# Check: origin/main must exist
git rev-parse --verify origin/main &>/dev/null || { echo "No origin/main found. Check remote configuration." >&2; exit 1; }

# Check: no uncommitted changes on main before switching
git switch main && git fetch origin && git pull --ff-only

# Check: branch doesn't already exist
if git rev-parse --verify "$BRANCH_NAME" &>/dev/null; then
  echo "Branch $BRANCH_NAME already exists." >&2
  if [[ -d "$WT_PATH" ]]; then
    echo "Worktree $WT_PATH already exists. Use resume-task instead." >&2
  fi
  exit 1
fi

# Check: worktree path doesn't already exist
if [[ -d "$WT_PATH" ]]; then
  echo "Worktree path $WT_PATH already exists. Use resume-task instead." >&2
  exit 1
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

echo "Created: branch=$BRANCH_NAME worktree=$(realpath "$WT_PATH")"
echo "Next: cd $WT_PATH && claude"
