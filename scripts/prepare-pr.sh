#!/usr/bin/env bash
# prepare-pr.sh — Create PR after prepare-push confirms readiness
# Usage: prepare-pr.sh [--draft]

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$PROJECT_DIR" ]] && { echo "Not a git repository." >&2; exit 1; }
cd "$PROJECT_DIR"

WORKTREE_PATH="$(git rev-parse --show-toplevel 2>/dev/null || echo '')"
WORKTREE_SLUG="$(basename "$WORKTREE_PATH")"

DRAFT=false
[[ "${1:-}" == "--draft" ]] && DRAFT=true

branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [[ "$branch" == "main" ]]; then
  echo "BLOCKED: Cannot create PR from main." >&2
  exit 1
fi

if ! git log --oneline origin/main..HEAD &>/dev/null; then
  echo "BLOCKED: No commits to create PR." >&2
  exit 1
fi

# Check remote branch exists
if ! git rev-parse --verify "origin/${branch}" &>/dev/null; then
  echo "BLOCKED: Remote branch origin/${branch} does not exist. Run prepare-push first." >&2
  exit 1
fi

echo "=== Creating Pull Request ==="
echo "Branch: $branch"
echo "Base: main"

# Gather info for PR body
diff_stats=$(git diff --stat origin/main..HEAD 2>/dev/null | tail -1)
changed_files=$(git diff --name-only origin/main..HEAD 2>/dev/null | head -10)
commit_msg=$(git log -1 --format="%B" origin/main..HEAD 2>/dev/null | head -3)

# AI-generated PR description
ai_pr_body=""
if command -v ccw &>/dev/null; then
  prompt="PURPOSE: Generate a GitHub PR description from branch context
TASK: Create a clear, concise PR description
CONTEXT:
=== Commit Message ===
$commit_msg

=== Diff Stats ===
$diff_stats

=== Changed Files ===
$changed_files

EXPECTED OUTPUT: Plain text PR body (no markdown code blocks), 3-5 sentences describing what this PR does and why
MODE: write"

  ai_pr_body=$(perl -e 'alarm shift; exec @ARGV' 30 -- ccw cli -p "$prompt" --tool gemini --mode write 2>&1) || true
fi

# Build PR body
if [[ -n "$ai_pr_body" ]]; then
  PR_BODY="$ai_pr_body"
else
  PR_BODY="## Summary
$commit_msg

## Changes
$diff_stats

## Files Changed
$changed_files"
fi

# Get remote URL for owner/repo
remote_url=$(git remote get-url origin 2>/dev/null || echo "")
# Parse GitHub owner/repo from URL (git@github.com:owner/repo.git or https://github.com/owner/repo.git)
if [[ "$remote_url" =~ git@github\.com:(.+)/(.+)\.git ]]; then
  gh_owner="${BASH_REMATCH[1]}"
  gh_repo="${BASH_REMATCH[2]}"
elif [[ "$remote_url" =~ https://github\.com/(.+)/(.+)\.git ]]; then
  gh_owner="${BASH_REMATCH[1]}"
  gh_repo="${BASH_REMATCH[2]}"
else
  gh_owner=""
  gh_repo=""
fi

echo ""
echo "PR Title: $(git log -1 --format="%s" origin/main..HEAD)"
echo ""
if [[ -n "$gh_owner" ]]; then
  echo "Repository: ${gh_owner}/${gh_repo}"
  if [[ "$DRAFT" == "true" ]]; then
    gh pr create --title "$(git log -1 --format="%s" origin/main..HEAD)" --body "$PR_BODY" --base main --head "$branch" --draft 2>&1
  else
    gh pr create --title "$(git log -1 --format="%s" origin/main..HEAD)" --body "$PR_BODY" --base main --head "$branch" 2>&1
  fi
  echo ""
  echo "PR created successfully!"
  gh pr view --web 2>/dev/null || true
else
  echo "Could not parse GitHub repo from remote URL: $remote_url"
  echo ""
  echo "Run manually:"
  echo "  gh pr create --title '$(git log -1 --format="%s" origin/main..HEAD)' --body '$PR_BODY' --base main --head $branch"
fi
