# Phase 1 Context — P0 Core Stability Fixes

## Phase Goal
Fix two P0 bugs: resume-task.sh parsing bug and doctor.sh staleness check bug.

## Requirements (from roadmap.md)

### P0-1: resume-task.sh 解析 bug 修复
- **Problem**: `git worktree list --porcelain` outputs entries separated by blank lines. `while read -r line` terminates early when encountering blank lines, causing incomplete worktree path parsing.
- **Fix**: Use `while IFS= read -r line` with blank line handling.
- **Success Criteria**: With >= 2 worktrees, all slugs/paths/branches are correctly parsed.

### P0-2: doctor.sh staleness 判断修复
- **Problem**: staleness uses `git log -1 --format="%ct"` (commit time). A 10-day-old commit = staleness, but metadata has `last_active_at` which is more accurate.
- **Fix**: Use `.worktree-first/worktrees/<slug>.json`'s `last_active_at` instead of commit time.
- **Success Criteria**: doctor.sh correctly distinguishes "active task" vs "long-inactive task".

## Files Needing Modification

### File 1: scripts/resume-task.sh
- **Line 11**: `git worktree list --porcelain | while read -r line; do`
- **Issue**: `read` returns false on blank lines, causing early loop termination
- **Fix**: `while IFS= read -r line` or use `awk` for proper parsing

### File 2: scripts/doctor.sh
- **Lines 45-53**: Staleness check using `git log -1 --format="%ct"`
- **Issue**: Uses commit timestamp, not metadata last_active_at
- **Fix**: Read from `.worktree-first/worktrees/<slug>.json` and use `last_active_at` field

## Test Infrastructure
- No existing test files for these scripts
- Need to create test scenarios with multiple worktrees

## Risks
- Modifying read loop behavior must not break existing functionality
- doctor.sh metadata reading must handle missing metadata files gracefully