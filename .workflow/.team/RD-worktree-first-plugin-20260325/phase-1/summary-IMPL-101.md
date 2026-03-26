# IMPL-101 Summary: guard拦截升级为auto-worktree引导

## Task ID
IMPL-101

## Status
completed

## Affected Files
- **Created**: `scripts/guard-auto-worktree.sh`
- **Modified**: `hooks/hooks.json`, `skills/start-task/SKILL.md`

## Changes Made

### scripts/guard-auto-worktree.sh (NEW)
- Merged guard-main-write.sh and guard-bash.sh logic into single script
- When user is on `main` branch and attempts Edit/Write/MultiEdit or dangerous Bash:
  - Auto-generates unique slug (`<type>-<timestamp>`)
  - Creates worktree at `../wt/<slug>` from origin/main
  - Creates metadata in `.worktree-first/worktrees/<slug>.json`
  - Returns deny JSON with guidance message to switch to new worktree
- Detects dangerous Bash commands (file-writing redirects, git push to main, --force, reset --hard, clean -x/-X, delete main/master)
- Configures new worktree with rerere.enabled and branch.autosetuprebase

### hooks/hooks.json
- Updated PreToolUse hook for Edit|Write|MultiEdit to call `guard-auto-worktree.sh` instead of `guard-main-write.sh`

### skills/start-task/SKILL.md
- Added "Auto-Worktree Behavior (Guard)" section documenting automatic worktree creation

## Verification
- [x] guard-auto-worktree.sh exists
- [x] bash -n syntax check passed
- [x] hooks.json valid JSON
- [x] File paths correct

## Notes
- Guard still blocks if user is on task branch but in main worktree directory (safety check)
- Auto-created worktrees use generated slugs; explicit naming requires manual /start-task
