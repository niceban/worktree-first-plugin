#!/usr/bin/env bash
# prepare-pr.sh — Generate PR description from task branch

set -euo pipefail

REPO_DIR=$(git rev-parse --show-toplevel 2>/dev/null || { echo "Not a git repository." >&2; exit 1; })
cd "$REPO_DIR"

branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

# Guard: must not be on main
if [[ "$branch" == "main" ]]; then
  echo "BLOCKED: Cannot prepare-pr from main." >&2
  exit 1
fi

# Guard: must have been pushed at least once
if ! git rev-parse --verify "origin/${branch}" &>/dev/null; then
  echo "Branch not pushed yet. Run prepare-push first." >&2
  exit 1
fi

# Collect info
title=$(echo "$branch" | sed 's/^task\///' | tr '-' ' ')
commits=$(git log origin/main..HEAD --oneline)
changed_files=$(git diff --stat origin/main..HEAD | tail -1)

cat <<EOF
## PR Title
$title

## Summary
<!-- 2-3 sentence description of what this task accomplishes -->

## Changes
$(echo "$changed_files")
$(git diff --name-only origin/main..HEAD | sed 's/^/- /')

## Commits
$commits

## Test Results
- [ ] Unit tests: <!-- pass/fail -->
- [ ] Integration tests: <!-- pass/fail -->
- [ ] Build: <!-- pass/fail -->

## Risk
- <!-- low/medium/high -->: <!-- description -->

## Rollback Plan
<!-- how to revert if this goes bad -->

## Notes
<!-- anything the reviewer should know -->
EOF
