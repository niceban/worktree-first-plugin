#!/usr/bin/env bash
# select-worktree.sh — Interactively select or create a worktree

set -euo pipefail

REPO_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$REPO_DIR" ]] && { echo "Not a git repository." >&2; exit 1; }
cd "$REPO_DIR"

WT_DIR="${REPO_DIR}/.worktree-first/worktrees"

# If no worktrees metadata exists, guide user to start-task
if [[ ! -d "$WT_DIR" ]] || [[ -z "$(ls -A "$WT_DIR" 2>/dev/null)" ]]; then
  echo ""
  echo "No active worktrees found."
  echo ""
  echo "To start a new task, run:"
  echo "  /worktree-first:start-task <type> <slug>"
  echo ""
  echo "Example: /worktree-first:start-task feat my-feature"
  echo ""
  exit 0
fi

# Collect worktree entries
entries=()
while IFS= read -r -d '' meta_file; do
  slug=$(basename "$meta_file" .json)
  branch=$(jq -r '.branch // ""' "$meta_file" 2>/dev/null)
  dirty=$(jq -r '.dirty // false' "$meta_file" 2>/dev/null)
  checkpoints_len=$(jq -r '.checkpoints | length // 0' "$meta_file" 2>/dev/null)
  last_active=$(jq -r '.last_active_at // ""' "$meta_file" 2>/dev/null)

  # Compute relative time
  if [[ -n "$last_active" ]]; then
    last_rel=$(date -d "$last_active" +%s 2>/dev/null || echo 0)
    now_ts=$(date +%s)
    age_secs=$((now_ts - last_rel))
    if [[ "$age_secs" -lt 60 ]]; then
      last_str="just now"
    elif [[ "$age_secs" -lt 3600 ]]; then
      mins=$((age_secs / 60))
      last_str="${mins}m ago"
    elif [[ "$age_secs" -lt 86400 ]]; then
      hours=$((age_secs / 3600))
      last_str="${hours}h ago"
    else
      days=$((age_secs / 86400))
      last_str="${days}d ago"
    fi
  else
    last_str="unknown"
  fi

  worktree_path=$(jq -r '.worktree // ""' "$meta_file" 2>/dev/null)
  entries+=("$slug|$branch|$dirty|$checkpoints_len|$last_str|$worktree_path")
done < <(find "$WT_DIR" -maxdepth 1 -name "*.json" -print0 2>/dev/null | sort -z)

# If no entries after reading
if [[ ${#entries[@]} -eq 0 ]]; then
  echo ""
  echo "No active worktrees found."
  echo ""
  echo "To start a new task, run:"
  echo "  /worktree-first:start-task <type> <slug>"
  echo ""
  exit 0
fi

echo ""
echo "=== Select Worktree ==="
idx=1
for entry in "${entries[@]}"; do
  IFS='|' read -r slug branch dirty checkpoints_len last_str worktree_path <<< "$entry"
  dirty_label="clean"
  if [[ "$dirty" == "true" ]]; then
    dirty_label="dirty"
  fi
  checkpoint_label="checkpoint"
  if [[ "$checkpoints_len" -ne 1 ]]; then
    checkpoint_label="checkpoints"
  fi
  printf "  [%d] %-12s %-6s %d %s  last: %s\n" "$idx" "$slug" "$dirty_label" "$checkpoints_len" "$checkpoint_label" "$last_str"
  idx=$((idx + 1))
done
echo "  [$idx] Start new task"
echo ""

echo -n "Pick a number or type a new task name: "
read -r user_input
echo ""

# Check if input is a number
if [[ "$user_input" =~ ^[0-9]+$ ]]; then
  user_num=$((user_input))
  if [[ "$user_num" -ge 1 ]] && [[ "$user_num" -lt "$idx" ]]; then
    # Valid worktree selection
    entry="${entries[$((user_num - 1))]}"
    IFS='|' read -r slug branch dirty checkpoints_len last_str worktree_path <<< "$entry"
    echo "Selected: $slug"
    echo ""
    echo "Worktree path: $worktree_path"
    echo ""
    echo "Next: cd $worktree_path && claude"
  elif [[ "$user_num" -eq "$idx" ]]; then
    # Start new task
    echo "To start a new task, run:"
    echo "  /worktree-first:start-task <type> <slug>"
    echo ""
    echo "Example: /worktree-first:start-task feat my-feature"
  else
    echo "Invalid selection: $user_input" >&2
    exit 1
  fi
else
  # Treat as new task name/slug
  slug="$user_input"
  echo "New task slug: $slug"
  echo ""
  echo "To start this task, run:"
  echo "  /worktree-first:start-task <type> $slug"
  echo ""
  echo "Example: /worktree-first:start-task feat $slug"
fi
