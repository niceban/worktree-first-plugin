# Phase 1 TODO List — P0 Core Stability Fixes

## Wave 1 (Parallel Execution)

### IMPL-P0-1: resume-task.sh parsing bug fix
- [ ] Read current scripts/resume-task.sh implementation (line 11)
- [ ] Fix `while read -r line` to `while IFS= read -r line` for blank line handling
- [ ] Test with 3+ worktrees to verify all parse correctly
- [ ] Verify single-worktree case still works

### IMPL-P0-2: doctor.sh staleness check fix
- [ ] Read current scripts/doctor.sh staleness logic (lines 45-53)
- [ ] Modify to read last_active_at from `.worktree-first/worktrees/<slug>.json`
- [ ] Add graceful fallback when metadata file missing
- [ ] Test: active task should not be marked stale
- [ ] Test: task with old commit but recent last_active_at should not be marked stale

## Verification Gates
- [ ] Both tasks complete code review
- [ ] All convergence criteria met
- [ ] Ready for VERIFY role