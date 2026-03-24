#!/usr/bin/env bash
# release-tag.sh — Create an annotated tag from clean main
# Usage: release-tag.sh <tag-name> [milestone|release]

set -euo pipefail

TAG_NAME="${1:-}"
TYPE="${2:-release}"

REPO_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$REPO_DIR" ]] && { echo "Not a git repository." >&2; exit 1; }
cd "$REPO_DIR"

# Guard: must be on main
branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [[ "$branch" != "main" ]]; then
  echo "BLOCKED: Tags must be created from main. Currently on: $branch" >&2
  exit 1
fi

# Guard: must have tag name
if [[ -z "$TAG_NAME" ]]; then
  echo "Usage: release-tag.sh <tag-name> [milestone|release]" >&2
  exit 1
fi

# Sync
git fetch origin
git pull --ff-only

# Guard: main must be clean — both diff AND status must be empty
# exit 0 if both are quiet, exit 1 if either has output
if ! git diff --quiet 2>/dev/null; then
  echo "BLOCKED: main has uncommitted changes (working tree dirty). Commit or stash first." >&2
  git status --short
  exit 1
fi

if ! git diff --cached --quiet 2>/dev/null; then
  echo "BLOCKED: main has staged changes (index dirty). Commit or unstage first." >&2
  git status --short
  exit 1
fi

# Guard: must be up to date with origin
if ! git diff --quiet origin/main 2>/dev/null; then
  echo "BLOCKED: main is behind origin/main. Pull and verify first." >&2
  exit 1
fi

# Guard: tag must not exist
if git rev-parse --verify "$TAG_NAME" &>/dev/null; then
  echo "BLOCKED: Tag '$TAG_NAME' already exists. Choose a different name." >&2
  exit 1
fi

# Create tag
if [[ "$TYPE" == "milestone" ]]; then
  full_tag="milestone-${TAG_NAME}"
  git tag -a "milestone-${TAG_NAME}" -m "milestone: ${TAG_NAME} on main"
else
  full_tag="$TAG_NAME"
  git tag -a "${TAG_NAME}" -m "release ${TAG_NAME}"
fi

sha=$(git log -1 --format="%H" -- "$full_tag")
echo "Created: $full_tag"
echo "SHA:     $sha"
echo ""
echo "Push with: git push origin ${full_tag}"
