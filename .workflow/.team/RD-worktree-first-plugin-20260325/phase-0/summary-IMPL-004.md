# IMPL-004 Summary: guard-bash.test.sh Extended Tests

## Task ID
IMPL-004

## Status
COMPLETED

## New Test Scenarios Added

### Test Group 1: Main Worktree Danger Detection
Tests that in main worktree (PWD == git root):
- File-writing commands are denied
- Safe redirects to /dev/null are allowed
- git push to main is denied
- Non-main push is allowed
- --force is denied, --force-with-lease is allowed
- git reset --hard bare form is denied
- git clean -x/-X is denied, -fd is allowed
- delete main/master is denied

### Test Group 2: Worktree Isolation (D5)
Tests that:
- main worktree detected correctly via `git worktree list`
- Idempotency check works

### Test Group 3: Worktree Detection (D4)
Tests that:
- `is_main_worktree()` correctly identifies main vs worktree
- Detection uses PWD == git_root (not branch == main)

## Test Results
38 tests passed, 0 failed

## Key Architecture Tested
- New detection: PWD == `git rev-parse --show-toplevel` (not branch == main)
- New behavior: worktree is isolated, all operations allowed inside
- Old scripts (guard-bash.sh, guard-main-write.sh) still work with new architecture

## File Modified
`/Users/c/auto-git/worktree-first-plugin/tests/guard-bash.test.sh`
