---
name: worktree-first:release-tag
description: Create an annotated tag from a clean main branch after verified stable state. Use when marking a milestone or production release. High-privilege operation — only for manual invocation.
disable-model-invocation: true
argument-hint: <tag-name> [milestone|release]
---

# /worktree-first:release-tag

Create an annotated tag from `main` after verified stable state.

## Invocation

- **Type**: user-only (high-privilege operation)
- **Command**: `/worktree-first:release-tag <tag-name> [milestone|release]`

## Pre-check

1. Must be on `main` branch
2. `main` must be clean (`git diff --quiet` and `git status --short` must return empty)
3. `main` must be up to date with `origin/main`
4. If tag already exists, warn and stop

## Tag type

- `milestone`: for internal checkpoints (e.g., `milestone-search-stable`)
- `release`: for formal releases (e.g., `v1.2.0`)

## Action

```bash
git fetch origin
git pull --ff-only

# Verify clean
git diff --quiet && git status --short || { echo "main is not clean"; exit 1; }

# Create annotated tag
if [ "$type" = "release" ]; then
  git tag -a "v${version}" -m "release v${version}"
else
  git tag -a "milestone-${name}" -m "milestone: ${name} on main"
fi

# Push tag
git push origin "v${version}"   # or milestone name
```

## Guard

- If not on `main`: "Tags must be created from `main`. Switch to main first."
- If main is dirty: "main must be clean before tagging. Commit or stash changes first."
- If `origin/main` behind: "main is behind `origin/main`. Pull and verify first."
- If tag exists: "Tag `v${version}` already exists. Choose a different version."

## Output

Confirm the tag SHA, name, message, and remind user to push: `git push --tags`.
