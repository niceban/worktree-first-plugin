# Gap Analysis: Requirements vs Current Implementation

## Requirement Coverage Matrix

| Requirement | Status | Evidence |
|-------------|--------|----------|
| 1. 新 session 入口展示 worktree/分支列表 | **MISSING** | No interactive entry point. `repo-status.sh` only prints on session start, doesn't offer selection. No `select-worktree.sh` exists. |
| 2. session 和分支关系要维护 | **MISSING** | No state persistence layer. No meta.json tracking session-to-branch mapping. |
| 3. 开发过程全流程 AI 判断 | **PARTIAL** | Hooks enforce rules (guard-*) but provide no AI judgment. `prepare-push.sh` runs validation but binary pass/fail only. |
| 4. 改动全程半成品，验收完才 commit | **PARTIAL** | `checkpoint.sh` exists but only creates commits — no AI validation that checkpoint is meaningful. No acceptance gate before squash. |
| 5. Git 状态和工作流状态要搭配 | **COVERED** | `guard-main-write.sh`, `guard-bash.sh`, `task-completed-check.sh` all enforce git+workflow alignment. |
| 6. 开工/收工两步自动化 | **COVERED** | `start-task.sh` automates branch+worktree creation. `finish-task.sh` automates cleanup. Both are complete. |

## Gap 1: No Interactive Worktree Selector at Session Entry

**Problem**: When user launches Claude in a project with existing worktrees, the system doesn't offer to pick one. User lands on `main`, sees a warning, then manually invokes `/worktree-first:resume-task`.

**What should exist**: A `select-worktree.sh` (or equivalent) that:
- Detects all existing worktrees on session start
- Presents a numbered interactive list with context (last checkpoint, dirty/clean, age)
- Launches Claude directly into the selected worktree directory
- Falls back to `start-task` if no worktrees exist

**Gap severity**: HIGH — this is the primary UX entry point and it's missing.

## Gap 2: Session-to-Branch Relationship Not Maintained

**Problem**: There's no persistent state that says "this Claude session is working on task X in worktree Y". If the agent restarts or the user resumes, there's no context continuity.

**What should exist**: A `session-state.json` or `meta.json` that tracks:
- Current task name / branch
- Worktree path
- Session start time
- Last activity timestamp
- Checkpoint count

**Gap severity**: HIGH — without this, AI can't provide contextual guidance ("you made 3 checkpoints, last one was 2 hours ago...").

## Gap 3: AI Judgment Is Binary Gates, Not Continuous Guidance

**Problem**: Current hooks are boolean — allow or deny. There is no AI-powered reflection layer that says "based on your diff, you might want to add a checkpoint before continuing".

**What should exist**: AI hooks at key decision points:
- After significant diff accumulation → "Should I checkpoint?"
- Before `prepare-push` → "Is this ready for review?"
- On `finish-task` → "Any untracked loose ends?"

**Gap severity**: MEDIUM — the workflow works but lacks intelligent guidance.

## Gap 4: Checkpoint Meaningfulness Not Validated

**Problem**: `checkpoint.sh` creates a commit on demand, but there's no AI check that the checkpoint represents a meaningful intent boundary. Users might checkpoint mid-thought.

**What should exist**: Pre-checkpoint AI analysis:
- Analyze staged diff size and scope
- If diff is trivial (<5 lines, mechanical), suggest to continue instead
- If diff is large (>500 lines), suggest splitting first

**Gap severity**: MEDIUM — current checkpoint is better than nothing, but not intelligent.

## Gap 5: No Progress Tracking Across Checkpoints

**Problem**: Checkpoints are just commits with messages. There's no way to see "checkpoint 3 of ~5" or overall progress toward PR-ready state.

**What should exist**: Checkpoint metadata or task progress view:
- `task-progress.sh` that shows: total checkpoints, recent activity, diff stats
- Visual indicator of where in the workflow the session is

**Gap severity**: LOW-MEDIUM — nice to have for large tasks.

## Summary

**Fully covered** (2): Git-workflow alignment (hooks), start/end automation
**Partially covered** (2): Checkpoint commits (no AI validation), AI judgment (binary gates only)
**Missing entirely** (2): Interactive worktree selector at session start, persistent session-branch relationship

**Priority**: Gap 1 and Gap 2 are foundational — the rest of the AI enhancement layer depends on them.
