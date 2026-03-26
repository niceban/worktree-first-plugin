# Worktree-First Plugin Evolution Roadmap

**Synthesizer**: synthesizer
**Session**: BRS-worktree-gap-20260324
**Date**: 2026-03-24
**Topic**: worktree-first插件当前改法 vs 原始需求的完整差距检查

---

## Executive Summary

This document synthesizes the gap analysis between the current worktree-first plugin implementation and the ideal worktree-first development workflow. The current implementation provides solid foundation with 8 skills and 5 hooks, but significant gaps exist in AI enhancement, architectural robustness, and user experience.

**Verdict**: The plugin addresses ~60% of the ideal worktree-first workflow. P0 focus should be on guard mechanism reliability and idempotency. P1 should address checkpoint flow automation. P2 should focus on AI-native features.

---

## Part 1: Core Gap Analysis (with Priorities)

### P0 - Critical Gaps (Must Fix)

| Gap ID | Category | Description | Impact |
|--------|----------|-------------|--------|
| G-01 | Architecture | **Non-idempotent scripts** - start-task.sh fails if worktree already exists instead of detecting and resuming | Workflow breakage |
| G-02 | Guard | **Incomplete dangerous command blocklist** - `git reset --hard` without path is not blocked, `git push --force` to main not blocked | Data loss risk |
| G-03 | Architecture | **No structured metadata storage** - worktree state is inferred from git, not explicitly tracked | Accuracy issues |
| G-04 | UX | **No rollback on failed rebase** - prepare-push stops on conflict but doesn't preserve original state | Workflow interruption |

### P1 - Important Gaps (Should Fix)

| Gap ID | Category | Description | Impact |
|--------|----------|-------------|--------|
| G-05 | UX | **No automatic worktree cleanup** - finish-task requires manual worktree removal after merge | User burden |
| G-06 | AI | **No automatic checkpoint message generation** - users must craft messages manually | Adoption barrier |
| G-07 | Architecture | **No worktree pooling** - each task creates new worktree, no reuse | Resource inefficiency |
| G-08 | Integration | **No GitHub API integration** - can't fetch PR status, can't auto-update PR description | Partial automation |
| G-09 | UX | **No progress indicators** - long operations (rebase, validation) show no feedback | Poor UX |
| G-10 | Guard | **Hook false positives** - post-edit-format runs even when no actual changes | Annoyance |

### P2 - Nice-to-Have (Consider for Future)

| Gap ID | Category | Description | Impact |
|--------|----------|-------------|--------|
| G-11 | AI | **LLM-powered commit message generation** | Productivity |
| G-12 | AI | **Intelligent task decomposition** - suggest task breakdown | Planning assist |
| G-13 | UX | **Worktree templates** - predefined worktree configs for project types | Flexibility |
| G-14 | Integration | **Cross-repo worktree support** - worktrees for dependencies | Advanced workflows |
| G-15 | Architecture | **Structured metadata store** (JSON/SQLite) for worktree lifecycle | Reliability |

---

## Part 2: Evolution Roadmap

### Phase P0: Foundation Stabilization (Weeks 1-2)

**Objective**: Fix critical gaps that cause workflow breakage or data loss.

#### P0.1: Idempotent Worktree Creation
```
Problem: start-task.sh fails if worktree exists
Solution: Detect existing worktree and offer to resume instead
Files: scripts/start-task.sh
Steps:
  1. Add pre-check: `git worktree list --porcelain | grep "<slug>$"`
  2. If exists, echo "Worktree already exists at ../wt/<slug>. Use /worktree-first:resume-task instead."
  3. Exit 0 with guidance instead of failing
```

#### P0.2: Dangerous Command Guard Enhancement
```
Problem: Some dangerous commands bypass guard-bash.sh
Commands to block:
  - `git reset --hard` (without explicit path - too risky)
  - `git push --force-with-lease origin main` (should only be blocked on main)
  - `git clean -fdx` (already blocked but patterns may miss variants)
Files: scripts/guard-bash.sh
Steps:
  1. Add pattern: `git\s+reset\s+--hard\s*$` (no path = block)
  2. Add pattern: `git\s+push\s+.*main\s*$` (block push to main)
  3. Test with: git reset --hard, git push -f origin main
```

#### P0.3: Rebase Rollback Mechanism
```
Problem: Failed rebase leaves repo in conflicted state with no easy rollback
Solution: Save pre-rebase state reference, offer rollback on failure
Files: scripts/prepare-push.sh
Steps:
  1. Before rebase: save `git rev-parse HEAD` to temp file
  2. On rebase failure: offer `git rebase --abort` using saved ref
  3. Add "Rollback available" message on failure
```

#### P0.4: Hook Reliability Improvements
```
Problem: post-edit-format runs even when no changes made
Solution: Compare pre/post file hashes before running format
Files: scripts/post-edit-format.sh
Steps:
  1. Calculate MD5 of staged files before format
  2. Run format
  3. Compare MD5 after - skip if identical
  4. Only report actual changes
```

---

### Phase P1: Workflow Enhancement (Weeks 3-5)

**Objective**: Reduce user burden, improve automation level.

#### P1.1: Automatic Worktree Cleanup
```
Problem: User must manually remove worktree after PR merge
Solution: Detect PR merge via GitHub API, auto-suggest cleanup
Files: scripts/finish-task.sh, hooks integration
Steps:
  1. Add optional `gh pr view --json state` check in finish-task
  2. If merged, auto-run `git worktree remove` after confirmation
  3. Add `--auto` flag for automated cleanup (CI/CD use case)
```

#### P1.2: Checkpoint Message Assistant
```
Problem: Users struggle with crafting good checkpoint messages
Solution: Generate suggestion based on staged diff
Files: scripts/checkpoint.sh
Steps:
  1. Parse staged diff for file names and change types
  2. Generate template: "checkpoint: <action> <primary-file>"
  3. Offer edit prompt before committing
  4. Learn from user edits over time (G-15 prerequisite)
```

#### P1.3: Worktree Pooling (Lightweight)
```
Problem: Creating new worktrees is slow for large repos
Solution: Maintain a pool of pre-created worktrees
Files: scripts/start-task.sh, scripts/resume-task.sh
Steps:
  1. On start-task, check if pooled worktree available
  2. If yes, reuse it with new branch
  3. Pool is refilled when worktree returned to pool
  4. Configurable pool size via setting
```

#### P1.4: Progress Indicators
```
Problem: Long operations (rebase, test-all) show no feedback
Solution: Add staged output with spinners/status
Files: scripts/prepare-push.sh, format scripts
Steps:
  1. Add "Rebasing..." → "Running validation..." → "Complete!" output
  2. Use `echo -ne` for inline progress
  3. Show elapsed time for operations > 3 seconds
```

---

### Phase P2: AI-Native Enhancement (Weeks 6-8)

**Objective**: Leverage LLMs for intelligent automation.

#### P2.1: LLM Commit Message Generation
```
Problem: Manual commit message writing breaks flow
Solution: Generate contextual messages from diff
Integration: Call LLM via `ccw cli` for message generation
Files: scripts/prepare-pr.sh, scripts/checkpoint.sh
Steps:
  1. Stage changes, capture diff
  2. Call: ccw cli -p "Generate commit message for: <diff>" --tool gemini
  3. Present suggestion, allow edit
  4. Use conventional commit format
```

#### P2.2: Intelligent Task Decomposition
```
Problem: Users create monolithic tasks that are hard to review
Solution: Analyze task scope, suggest breakdown
Integration: Team coordination with planning agent
Files: skills/start-task/SKILL.md
Steps:
  1. On start-task, analyze task name and existing code
  2. Call planning agent for breakdown suggestion
  3. Offer: proceed with original, use suggestion, or modify
  4. Track decomposition patterns for future suggestions
```

#### P2.3: PR Description Auto-Generation
```
Problem: Writing PR descriptions is tedious and often incomplete
Solution: Generate from commits + diff + task context
Files: scripts/prepare-pr.sh
Steps:
  1. Collect: commit messages, diff stats, related issues
  2. Call LLM with template: "Generate PR description from: <data>"
  3. Include: Summary, Changes, Testing, Notes sections
  4. Allow inline editing before creating PR
```

#### P2.4: Structured Metadata Store
```
Problem: Worktree state inferred from git, error-prone
Solution: JSON metadata file per worktree
Location: `.worktree-first/worktrees/<slug>.json`
Schema:
{
  "slug": "auth-timeout",
  "branch": "task/fix-auth-timeout",
  "created": "2026-03-24T10:00:00Z",
  "last_active": "2026-03-24T15:30:00Z",
  "status": "active|paused|ready-to-push|merged|abandoned",
  "checkpoints": 5,
  "pr_url": null
}
Files: All scripts that modify worktree state
Steps:
  1. Create .worktree-first/ directory on init
  2. Update metadata on every state change
  3. Enable richer resume-task output
  4. Power doctor diagnostics
```

---

## Part 3: Implementation Dependencies

### Dependency Graph

```
P0.1 (Idempotent start)
    ↓
P0.2 (Dangerous guard) ← Independent
    ↓
P0.3 (Rebase rollback) ← Independent
    ↓
P0.4 (Hook reliability) ← Independent
    ↓
P1.1 (Auto cleanup) ← Requires P0.1
    ↓
P1.2 (Checkpoint assist) ← Independent
    ↓
P1.3 (Worktree pooling) ← Requires P0.1
    ↓
P1.4 (Progress UI) ← Independent
    ↓
P2.1 (LLM commit msgs) ← Independent
    ↓
P2.2 (Task decomposition) ← Independent
    ↓
P2.3 (PR auto-desc) ← Requires P2.1
    ↓
P2.4 (Metadata store) ← Requires P1.1, P1.2
```

---

## Part 4: Files to Modify

| Phase | File | Changes |
|-------|------|---------|
| P0.1 | scripts/start-task.sh | Idempotent worktree detection |
| P0.2 | scripts/guard-bash.sh | Enhanced dangerous command patterns |
| P0.3 | scripts/prepare-push.sh | Pre-rebase state save, rollback offer |
| P0.4 | scripts/post-edit-format.sh | Hash-based change detection |
| P1.1 | scripts/finish-task.sh | GitHub API merge detection |
| P1.2 | scripts/checkpoint.sh | Message generation from diff |
| P1.3 | scripts/start-task.sh, resume-task.sh | Worktree pooling logic |
| P1.4 | scripts/prepare-push.sh, format scripts | Progress indicators |
| P2.1 | scripts/checkpoint.sh, prepare-pr.sh | LLM integration |
| P2.2 | skills/start-task/SKILL.md | Planning agent integration |
| P2.3 | scripts/prepare-pr.sh | Enhanced PR generation |
| P2.4 | All scripts | Metadata store updates |

---

## Appendix: Current Implementation Coverage

| Component | Status | Notes |
|-----------|--------|-------|
| start-task | 70% | Missing idempotency |
| resume-task | 60% | Missing metadata store |
| checkpoint | 50% | Missing message assist |
| prepare-push | 65% | Missing rollback |
| prepare-pr | 40% | Missing LLM generation |
| finish-task | 55% | Missing auto-cleanup |
| release-tag | 80% | Works correctly |
| doctor | 75% | Missing predictive analysis |
| guard-main-write | 85% | Works correctly |
| guard-dangerous-bash | 70% | Missing patterns |
| post-edit-format | 60% | False positives |
| task-completed-gate | 80% | Works correctly |
| session-start-inject | 90% | Works correctly |

---

## Appendix: Testing Checklist

### P0 Verification
- [ ] `start-task` run twice with same slug → second run shows guidance, doesn't fail
- [ ] `git reset --hard` on main → blocked
- [ ] `git push origin main` → blocked
- [ ] Failed rebase → rollback offered
- [ ] Edit file without changes → format not triggered

### P1 Verification
- [ ] PR merged on GitHub → cleanup suggested
- [ ] Checkpoint with staged changes → message suggested
- [ ] Multiple start-task calls → pool reused
- [ ] prepare-push → shows progress stages

### P2 Verification
- [ ] Checkpoint → LLM message generation works
- [ ] start-task large feature → decomposition suggested
- [ ] prepare-pr → full PR description generated
- [ ] Metadata store → all scripts update correctly
