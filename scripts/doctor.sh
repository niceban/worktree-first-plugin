#!/usr/bin/env bash
# doctor.sh — Audit all worktrees and branches, report issues (read-only)

set -euo pipefail

REPO_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$REPO_DIR" ]] && { echo "Not a git repository." >&2; exit 1; }
cd "$REPO_DIR"

FIX_MODE=false
[[ "${1:-}" == "--fix" ]] && FIX_MODE=true

exit_code=0

echo "=== Worktree Audit ==="

# Parse worktree list --porcelain into fields
git worktree list --porcelain | awk '
  $1 == "path" { path = $2; next }
  $1 == "branch" { branch = $2; next }
  $1 == "HEAD" { head = $2; next }
  $1 == "locked" { locked = 1; next }
  $0 ~ /^[^ ]/ && path != "" {
    # End of this worktree entry — process it
    print "PATH:" path
    print "BRANCH:" branch
    print "HEAD:" head
    print "LOCKED:" (locked == 1 ? "yes" : "no")
    print "---"
    path = ""; branch = ""; head = ""; locked = 0
  }
  END {
    if (path != "") {
      print "PATH:" path
      print "BRANCH:" branch
      print "HEAD:" head
      print "LOCKED:" (locked == 1 ? "yes" : "no")
    }
  }
' | while IFS= read -r line; do
  case "$line" in
    PATH:*) path="${line#PATH:}"; echo ""; echo "  path: $path" ;;
    BRANCH:*) branch="${line#BRANCH:}"; echo "  branch: $branch" ;;
    HEAD:*)
      head="${line#HEAD:}"
      commit_msg=$(git log -1 --format="%h %s" "$head" 2>/dev/null || echo "unknown")
      echo "  HEAD:   $commit_msg"

      # Staleness check: Use metadata last_active_at if available, fallback to git commit time
      last_ts=0
      slug=$(basename "$path")
      meta_file="${REPO_DIR}/.worktree-first/worktrees/${slug}.json"

      if [[ -f "$meta_file" ]]; then
        last_active=$(jq -r '.last_active_at // empty' "$meta_file" 2>/dev/null || echo "")
        if [[ -n "$last_active" ]]; then
          if [[ "$(uname)" == "Darwin" ]]; then
            last_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_active" +%s 2>/dev/null || echo 0)
          else
            last_ts=$(date -d "$last_active" +%s 2>/dev/null || echo 0)
          fi
        fi
      fi

      # Fallback to commit time if metadata missing or failed to parse
      if [[ "$last_ts" -eq 0 ]]; then
        last_ts=$(git log -1 --format="%ct" "$head" 2>/dev/null || echo "0")
      fi

      if [[ -n "$last_ts" ]] && [[ "$last_ts" != "0" ]]; then
        now_ts=$(date +%s)
        age_days=$(( (now_ts - last_ts) / 86400 ))
        if [[ "$age_days" -gt 7 ]]; then
          echo "  [WARN] Stale: no activity in ${age_days} days"
          exit_code=1
        fi
      fi
      ;;

    LOCKED:*) [[ "$line" == *"yes"* ]] && echo "  [LOCKED]" ;;
    ---*) ;;  # separator, skip
  esac
done

echo ""
echo "=== Remote Branch Audit ==="

echo ""
echo "=== Orphaned Metadata Cleanup ==="
META_DIR="${REPO_DIR}/.worktree-first/worktrees"
if [[ ! -d "$META_DIR" ]]; then
  echo "  (no metadata directory)"
else
  # Get list of actual worktree paths from git
  actual_worktrees=$(git worktree list --porcelain | awk '$1 == "path" { print $2 }' | while IFS= read -r p; do basename "$p"; done | sort)

  # Get list of metadata slugs
  if [[ -d "$META_DIR" ]]; then
    metadata_slugs=$(ls "$META_DIR"/*.json 2>/dev/null | while IFS= read -r f; do basename "$f" .json; done | sort)
  else
    metadata_slugs=""
  fi

  orphaned=0
  while IFS= read -r slug; do
    [[ -z "$slug" ]] && continue
    # Check if this slug has a corresponding worktree
    if ! echo "$actual_worktrees" | grep -qxF "$slug"; then
      orphaned=1
      if [[ "$FIX_MODE" == "true" ]]; then
        rm -f "${META_DIR}/${slug}.json"
        echo "  [FIX] Removed orphaned metadata: $slug"
      else
        echo "  [ORPHAN] $slug — no corresponding worktree (run with --fix to clean)"
      fi
    fi
  done <<< "$metadata_slugs"

  [[ "$orphaned" == "0" ]] && echo "  (no orphaned metadata)"
fi

echo ""
echo "=== Metadata Integrity Check ==="
META_DIR="${REPO_DIR}/.worktree-first/worktrees"
if [[ ! -d "$META_DIR" ]]; then
  echo "  (no metadata directory)"
else
  integrity_ok=true
  for meta_file in "$META_DIR"/*.json; do
    [[ -f "$meta_file" ]] || continue
    slug=$(basename "$meta_file" .json)

    # Validate JSON with jq
    if ! jq empty "$meta_file" 2>/dev/null; then
      integrity_ok=false
      echo "  [CORRUPT] $slug — invalid JSON"
      if [[ "$FIX_MODE" == "true" ]]; then
        # Rebuild minimal metadata from git worktree info
        wt_path=$(git worktree list --porcelain 2>/dev/null | awk -v s="$slug" '$1 == "path" { if (basename($2) == s) print $2 }')
        branch=$(git worktree list --porcelain 2>/dev/null | awk -v s="$slug" '$1 == "branch" { if (basename($2) == s) print $2 }')
        if [[ -n "$wt_path" ]]; then
          cat > "$meta_file" <<EOF
{
  "slug": "$slug",
  "branch": "${branch:-task/$slug}",
  "worktree": "$(realpath "$wt_path")",
  "status": "active",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_active_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "dirty": false,
  "checkpoints": [],
  "last_checkpoint_message": null,
  "pr_url": null
}
EOF
          echo "  [FIX] Rebuilt metadata for: $slug"
        else
          rm -f "$meta_file"
          echo "  [FIX] Removed corrupt metadata (no corresponding worktree): $slug"
        fi
      fi
      exit_code=1
      continue
    fi

    # Validate required fields
    required_fields="slug branch status created_at last_active_at"
    for field in $required_fields; do
      if ! jq -e "has(\"$field\")" "$meta_file" > /dev/null 2>&1; then
        integrity_ok=false
        echo "  [CORRUPT] $slug — missing field: $field"
        exit_code=1
      fi
    done
  done
  [[ "$integrity_ok" == "true" ]] && echo "  (all metadata files are valid)"
fi

for rbranch in $(git branch -r --list 'origin/task/*' --format='%(refname:short)' 2>/dev/null); do
  ahead_count=$(git log "${rbranch}..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  behind_count=$(git log "HEAD..${rbranch}" --oneline 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  if [[ "$ahead_count" -eq 0 ]] && [[ "$behind_count" -eq 0 ]]; then
    # Check if local worktree exists for this branch
    local_branch="${rbranch#origin/}"
    if ! git worktree list --porcelain 2>/dev/null | grep -q "branch.*${local_branch}$"; then
      echo "  [ORPHAN] $rbranch — no local worktree, likely merged and abandoned"
      exit_code=1
    fi
  fi
done

echo ""
echo "=== Local-Only Task Branches (no remote) ==="
has_local_only=0
for lbranch in $(git branch --list 'task/*' --format='%(refname:short)' 2>/dev/null); do
  if ! git rev-parse --verify "origin/${lbranch}" &>/dev/null; then
    unpushed=$(git log origin/main.."${lbranch}" --oneline 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    echo "  [LOCAL] $lbranch — $unpushed unpushed commit(s) (never pushed)"
    has_local_only=1
  fi
done
[[ "$has_local_only" -eq 0 ]] && echo "  (none)"

echo ""
echo "=== Rebase Reminder (task branches behind main) ==="
behind_count=0
for branch in $(git branch --list 'task/*' --format='%(refname:short)' 2>/dev/null); do
  ahead=$(git log "origin/main..${branch}" --oneline 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  behind=$(git log "${branch}..origin/main" --oneline 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  if [[ "$behind" -gt 5 ]]; then
    echo "  [WARN] $branch is ${behind} commits behind main — rebase recommended"
    echo "         Run: git rebase origin/main"
    behind_count=$((behind_count + 1))
    exit_code=1
  fi
done
[[ "$behind_count" -eq 0 ]] && echo "  (all task branches are current with main)"

echo ""
echo "=== Commit Hygiene ==="
has_hygiene_issues=0
for branch in $(git branch --list 'task/*' --format='%(refname:short)' 2>/dev/null); do
  commits=$(git log --oneline origin/main.."${branch}" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  if [[ "$commits" -gt 20 ]]; then
    last_msg=$(git log -1 --format="%s" -- "$branch" 2>/dev/null || true)
    if [[ "$last_msg" =~ ^checkpoint: ]]; then
      echo "  [WARN] $branch has $commits commits, all checkpoints — never reviewed/cleaned"
      has_hygiene_issues=1
      exit_code=1
    fi
  fi
done
[[ "$has_hygiene_issues" -eq 0 ]] && echo "  (no hygiene issues)"

echo ""
if [[ "$exit_code" -eq 0 ]]; then
  echo "Doctor: No issues found."
else
  echo "Doctor: Warnings found (see above)."
fi

exit "$exit_code"
