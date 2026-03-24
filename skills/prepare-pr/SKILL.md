---
name: worktree-first:prepare-pr
description: Generate a PR description from the task branch diff and commits. Use after prepare-push when ready to open a pull request. Outputs a copy-paste-ready PR description.
allowed-tools: Bash
---

# /worktree-first:prepare-pr

Prepare a PR description after push: summarize changes, scope, test results, and risk.

## Invocation

- **Type**: user-or-model
- **Command**: `/worktree-first:prepare-pr`

## Pre-check

1. Must be inside a task worktree
2. Branch must have been pushed (at least one push exists)
3. Branch must be rebased onto latest `origin/main`

## Action

1. Collect diff summary:

```bash
git fetch origin
git diff origin/main..HEAD --stat
```

2. List all commits in the PR:

```bash
git log origin/main..HEAD --oneline
```

3. Run a quick status:

```bash
git status --short
```

4. Generate PR description from template:

```
## Summary
<!-- 2-3 sentence description of what this task accomplishes -->

## Changes
<!-- files changed and why -->

## Test Results
- [ ] Unit tests: <pass/fail/none>
- [ ] Integration tests: <pass/fail/none>
- [ ] Build: <pass/fail/none>

## Risk
- <low/medium/high>: <description>

## Rollback Plan
<!-- how to revert if this goes bad -->

## Notes
<!-- anything the reviewer should know -->
```

5. Output the full PR description so user can copy-paste into GitHub UI, or offer to create PR via `gh pr create` if `gh` CLI is available.

## Guard

- If branch not yet pushed: "Push the branch first with `/worktree-first:prepare-push`, then run this."
- If branch is not rebased onto latest main: "Rebase onto latest main first."
