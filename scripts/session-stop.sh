#!/usr/bin/env bash
# session-stop.sh — Update metadata on session end (SessionStop hook)

set -euo pipefail

WORKTREE_PATH="$(git rev-parse --show-toplevel 2>/dev/null || echo '')"
[[ -z "$WORKTREE_PATH" ]] && exit 0

REPO_DIR="$(git rev-parse --git-dir 2>/dev/null || echo '')"
[[ -z "$REPO_DIR" ]] && exit 0
REPO_DIR="$(dirname "$REPO_DIR")"

SLUG="$(basename "$WORKTREE_PATH")"
META_FILE="${REPO_DIR}/.worktree-first/worktrees/${SLUG}.json"

if [[ -f "$META_FILE" ]]; then
  # Backup before writing
  backup_dir="${META_FILE}.backups"
  mkdir -p "$backup_dir"
  cp "$META_FILE" "${backup_dir}/$(date -u +%Y%m%d-%H%M%S).json"
  ls -1t "$backup_dir" | tail -n +4 | xargs -r rm -f

  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq \
    --arg now "$now" \
    '.last_active_at = $now' "$META_FILE" > "${META_FILE}.tmp" && mv "${META_FILE}.tmp" "$META_FILE"
fi

exit 0
