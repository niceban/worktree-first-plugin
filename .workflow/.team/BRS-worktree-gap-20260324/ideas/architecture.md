# Architecture: Current Skeleton and Extension Viability

## Current Architecture Assessment

```
worktree-first-plugin/
├── scripts/          # Pure bash, no state, no AI
├── skills/           # SKILL.md definitions (metadata only)
├── hooks/            # Event-driven enforcement (PreToolUse, PostToolUse, TaskCompleted)
└── .claude-plugin/   # Plugin manifest
```

**Design pattern**: Event-driven enforcement via hooks + manual skill invocation. Stateless scripts. No central coordinator.

## Extension Viability Analysis

### 1. Interactive Worktree Selector (Gap 1)

**Can current architecture support?**: PARTIALLY

**What's needed**:
- A new script `select-worktree.sh` that can be invoked at session start
- Integration with `repo-status.sh` to provide richer context per worktree
- A way to redirect the Claude session into a worktree directory after selection

**Current gap**: `repo-status.sh` runs on `SessionStart` but outputs text only — it cannot redirect the session. The hook system is fire-and-forget.

**Proposed addition**:
```
scripts/
  select-worktree.sh    # Interactive selector, outputs "cd <path> && claude" guidance
```

**Viability**: Feasible as a new script, but requires user to manually `cd` and re-launch Claude. No automatic redirect capability within current hook system.

---

### 2. Session-Branch State Persistence (Gap 2)

**Can current architecture support?**: NO

**What's needed**:
- A state file (e.g., `.worktree-first/state.json`) that persists across sessions
- A "current task" concept that survives Claude restarts
- A state manager script that reads/writes this state

**Current gap**: Scripts are stateless. No directory for plugin state. `hooks/hooks.json` has no "SessionResume" trigger.

**Proposed addition**:
```
.worktree-first/
  meta.json          # { current_task, current_worktree, last_checkpoint, session_history }
  state.json          # { branch, dirty, unpushed_count, checkpoint_count }
```

**Viability**: Feasible as file-based state, but needs a new "SessionResume" hook or polling mechanism to reload state on re-entry. Current architecture has no way to inject state back into Claude context on resume.

---

### 3. AI Judgment Layer (Gap 3)

**Can current architecture support?**: PARTIALLY

**What's needed**:
- A way to invoke AI analysis at key points (checkpoint, before push, during session)
- A hook type for "AI advisory" (not just enforce/deny)
- Structured output from AI that can drive workflow decisions

**Current gap**: All hooks return `permissionDecision: allow/deny`. No hook for "ask AI for opinion". Scripts are bash-only, no AI invocation.

**Proposed addition**:
```
scripts/
  ai-checkpoint-advisor.sh   # Invoke AI to assess if checkpoint is meaningful
  ai-push-readiness.sh       # Invoke AI to assess if ready for PR
  ai-progress_estimator.sh  # Invoke AI to estimate completion %

hooks/
  SessionStart: → ai-session-advisor.sh (suggest which worktree, provide context)
  PreCheckpoint: → ai-checkpoint-advisor.sh (intercept, advise continue or checkpoint)
  PrePreparePush: → ai-push-readiness.sh (intercept, assess readiness)
```

**Viability**: Feasible if we add AI CLI invocation (`ccw cli`) to scripts. Hook system supports new script paths. But we need a "hook that asks AI and continues" vs current "hook that blocks or allows".

---

### 4. Checkpoint Validation (Gap 4)

**Can current architecture support?**: YES

**What's needed**:
- Pre-checkpoint analysis of staged diff
- Advice on whether to checkpoint or continue
- Integration with `checkpoint.sh`

**Current gap**: `checkpoint.sh` has no diff analysis step (lines 22-27 just check staging state).

**Proposed change to `checkpoint.sh`**:
- Add `ai-checkpoint-advisor.sh` call before committing
- If AI advises "continue working", exit without committing

**Viability**: Straightforward — script modification, no architecture change needed.

---

### 5. Progress Tracking (Gap 5)

**Can current architecture support?**: YES

**What's needed**:
- Aggregate checkpoint history for a task
- A `task-progress.sh` script that summarizes

**Current gap**: `checkpoint.sh` creates commits but doesn't update any progress tracker.

**Proposed addition**:
```
scripts/
  task-progress.sh    # Show: checkpoint count, diff stats, time spent, completion estimate
```

**Viability**: Straightforward — script reads git log and worktree state, no new architecture needed.

---

## Critical Architecture Weaknesses

### 1. No "Session Resume" Hook

When Claude restarts mid-task, there is no hook that fires to reload session state. `SessionStart` fires but doesn't have access to "this session previously worked on X". The session context is ephemeral.

**Impact**: Gap 2 (session state) cannot be properly implemented without a `SessionResume` equivalent.

### 2. Hooks Cannot Modify Session Behavior

Current hooks can only `allow` or `deny`. They cannot:
- Redirect to a different directory
- Set a session variable
- Inject AI analysis into the conversation

**Impact**: Gap 1 (interactive selector) requires manual user action after the hook runs.

### 3. No State Directory

The plugin has no `$REPO_DIR/.worktree-first/` directory for persistent state. All state is ephemeral in git commits or script variables.

**Impact**: Gap 2 (session state) needs a home. Must be added.

### 4. Scripts Are Pure Bash, No AI Integration Point

Every script is `#!/usr/bin/env bash` with no AI invocation. Adding AI judgment requires either:
- Embedding `ccw cli` calls directly in scripts
- Creating a separate AI advisor layer

**Impact**: Gap 3 (AI judgment) is architecturally possible but adds complexity to every script that needs AI.

---

## Recommended Architecture Changes

1. **Add state directory**: `.worktree-first/meta.json` for session-task mapping
2. **Add "SessionResume" equivalent**: A hook or script that runs on re-entry to restore context
3. **Add AI advisor scripts**: `*-advisor.sh` scripts that invoke AI and return structured advice
4. **Add progress tracker**: Lightweight JSON in state directory tracking checkpoint count and activity
5. **Add select-worktree.sh**: Interactive selector as entry point, backed by state for "last used" ranking
