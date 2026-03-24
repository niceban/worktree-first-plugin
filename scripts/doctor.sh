#!/usr/bin/env bash
# doctor.sh — Audit all worktrees and branches, report issues (read-only)

set -euo pipefail

REPO_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$REPO_DIR" ]] && { echo "Not a git repository." >&2; exit 1; }
cd "$REPO_DIR"

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
      # Staleness check using git log -1 --format=%ct (unix timestamp)
      last_ts=$(git log -1 --format="%ct" "$head" 2>/dev/null || echo "0")
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
