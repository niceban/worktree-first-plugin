# User Experience: Breakpoints and Flow Analysis

## Current User Flow vs Ideal Flow

### Current Flow (Problematic)

```
User launches Claude in project dir
  → lands on main branch
  → sees repo-status warning: "use start-task"
  → must manually: /worktree-first:start-task feat xyz
  → cd ../wt/xyz && claude
  → [work on code]
  → /worktree-first:checkpoint  (if remembers)
  → [more work]
  → /worktree-first:prepare-push
  → git push manually
  → /worktree-first:prepare-pr
  → /worktree-first:finish-task
```

**Problems**:
1. No prompt to resume existing worktree on session start
2. Entry point is "start new" not "resume or start"
3. No indication of which worktree to pick when multiple exist
4. Checkpoint is opt-in, not guided
5. No sense of progress toward PR readiness

### Ideal Flow

```
User launches Claude in project dir
  → sees interactive worktree selector (or "start new task" option)
    - "Resume: search-index (3 checkpoints, dirty, 2h ago)"
    - "Resume: auth-fix (1 checkpoint, clean, 5m ago)"
    - "Start new task"
  → selects worktree → Claude enters that directory
  → AI provides context: "Resuming search-index, last checkpoint: 'parser refactor compiles'"
  → [work on code]
  → AI suggests: "You've been working for 45m with no checkpoint. Want to save progress?"
  → /checkpoint or "continue"
  → [more work]
  → AI assesses: "This looks PR-ready. 1 commit, clean diff, tests pass. Prepare push?"
  → yes → AI runs prepare-push checks
  → AI summarizes: "Ready. 1 commit ahead of main. Open PR?"
  → finish-task
```

**Benefits**:
1. Entry point is a choice, not a command
2. Existing work is surfaced, not hidden
3. AI guides checkpoint frequency
4. Progress is visible at all times

---

## Breakpoint 1: Session Entry (Highest Priority)

**Current state**: `repo-status.sh` prints branch/status on every session start. No interaction.

**User experience at this breakpoint**:
- User sees text output they may not read
- If on main: warning to use start-task
- If on task branch in main repo (not worktree): confusing error from guard-main-write.sh
- No option to pick from existing worktrees

**What user sees**:
```
=== Repo Status ===
branch:     main
status:     clean
is_worktree: false

Recent commits:
  abc1234feat: initial impl
  def5678 fix: typo

  [WARN] Currently on main. Use /worktree-first:start-task to create a task worktree.
```

**What should happen**:
```
=== Worktree Selector ===
You have 2 active worktrees:
  [1] search-index  (feat/search-index)  dirty  3 checkpoints  last: 2h ago
  [2] auth-fix      (feat/auth-fix)       clean  1 checkpoint   last: 5m ago
  [3] Start new task

Pick a number or task name:
```

**Gap**: No script produces this UI. `resume-task.sh` comes closest but requires manual invocation and doesn't rank by recency.

---

## Breakpoint 2: Mid-Development Checkpoint Decision

**Current state**: Checkpoint is purely manual. User must remember to run `/worktree-first:checkpoint`.

**User experience at this breakpoint**:
- User edits for 30+ minutes
- No reminder or prompt
- Risk: if Claude crashes, significant work is lost (only in git diff, not committed)

**What should happen**:
- AI monitors session activity (time since last checkpoint, diff size)
- After ~30min of dirty work without checkpoint, AI prompts:
  > "You've been working for 32 minutes with uncommitted changes. Recommend a checkpoint before continuing. Run `/worktree-first:checkpoint` or say 'continue'."

**Gap**: No advisor script monitors session time and prompts proactively.

---

## Breakpoint 3: Pre-Push Readiness

**Current state**: `prepare-push.sh` runs rebase + squash + validation. If validation fails, it blocks. But it doesn't tell the user WHY or what to fix.

**User experience at this breakpoint**:
```
=== Ready to push ===
Branch: feat/search-index
Commits to push:
  abc1234 feat: search index impl

Run: git push --force-with-lease -u origin feat/search-index
(This plugin does not auto-push — confirm manually)
```

**What should happen**:
```
=== Pre-Push Assessment ===
AI analysis of your branch:
  - Diff size: 847 lines (reasonable)
  - Files changed: 12 (focused scope)
  - Test coverage: 78% (good)
  - Checkpoint history: 4 meaningful checkpoints
  - Risk: MEDIUM (no integration test)

Recommendation: Ready to push. Consider adding an integration test
if the search spans multiple services.

Proceed with push? [y/n]
```

**Gap**: `prepare-push.sh` validates but doesn't analyze or advise. User gets binary pass/fail.

---

## Breakpoint 4: Task Completion Check

**Current state**: `task-completed-check.sh` blocks TaskCompleted if conditions aren't met. But it doesn't tell user what "done" looks like.

**User experience at this breakpoint**:
- User tries to mark task complete
- Gets blocked: "Last commit is a checkpoint and has not been reviewed"
- User confused: what does "reviewed" mean? Who reviews?

**What should happen**:
- AI could pre-assess whether task is truly complete:
  - Are there unhandled TODO/FIXME comments?
  - Are there related files that weren't modified?
  - Does the diff look complete for the stated goal?

**Gap**: No AI pre-assessment before task completion gate.

---

## Breakpoint 5: Worktree Switching (Multi-Worktree Confusion)

**Current state**: When user has 3+ worktrees, it's hard to track which is which. `resume-task.sh` lists them but doesn't show what each one is working on.

**User experience at this breakpoint**:
```
=== Active Worktrees ===
  path:    /Users/x/proj/wt/search-index
  branch:  feat/search-index
  HEAD:    abc1234 feat: search index impl

  path:    /Users/x/proj/wt/auth-fix
  branch:  feat/auth-fix
  HEAD:    def5678 fix: auth timeout
```

**What should happen**:
```
=== Active Worktrees ===
  [1] search-index  feat/search-index  dirty     "search index impl"       3 checkpoints
  [2] auth-fix       feat/auth-fix      clean     "auth timeout fix"        1 checkpoint
  [3] ui-redesign    feat/ui-redesign   clean     "button refactor"         0 checkpoints

Last session was in [1]. Resume? [Y/n]
```

**Gap**: `resume-task.sh` doesn't know which was last used. No recency ranking.

---

## UX Principles for Fixes

1. **Default to resume, not start new**: When worktrees exist, offer to resume first
2. **Show context, not just state**: "dirty" is less useful than "dirty, 45min since last checkpoint"
3. **Proactive guidance**: AI should prompt before problems occur (time to checkpoint, behind main)
4. **Binary is not enough**: Don't just allow/deny — explain WHY and what to do next
5. **Make progress visible**: Checkpoint count, diff size trend, time in session

---

## Top 3 UX Improvements by Impact

1. **Add interactive worktree selector at entry** (Breakpoint 1)
   - Highest impact, first impression
   - Makes existing work discoverable

2. **Add checkpoint reminder advisor** (Breakpoint 2)
   - Prevents work loss
   - Low implementation cost (add AI advisor script)

3. **Rich pre-push assessment** (Breakpoint 3)
   - Makes the push decision informed, not blind
   - Transforms prepare-push from gate to guide
