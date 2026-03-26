# AI Enhancement: Where to Add AI Judgment Nodes

## Overview

The current plugin is purely rule-based: hooks enforce git state, scripts validate, but nothing "thinks" about whether the workflow is going well. AI enhancement adds advisory nodes where mechanical rules are insufficient.

## AI Judgment Node Map

```
Session Start
  └─→ Node 1: Worktree Selection Advisor
        Input: all worktrees, git log, checkpoint history, recency
        Output: recommendation + context summary

During Development
  └─→ Node 2: Checkpoint Advisor (on staged changes)
        Input: staged diff, time since last checkpoint, checkpoint history
        Output: "checkpoint now" / "continue working" / "split first"

  └─→ Node 3: Mid-Session Checkpoint Reminder (time-based)
        Input: session duration, diff size, last checkpoint time
        Output: proactive reminder to checkpoint

Before Prepare-Push
  └─→ Node 4: Push Readiness Assessor
        Input: full diff, checkpoint history, test results, file count
        Output: readiness score + specific improvement suggestions

Before Finish-Task
  └─→ Node 5: Completion Readiness Check
        Input: all files touched, TODO/FIXME scan, diff completeness
        Output: "done" / "almost done, missing X" / "incomplete"

On Session Resume
  └─→ Node 6: Context Restorer
        Input: session history, checkpoint log, last activity
        Output: "You left off at X, your last checkpoint was Y"
```

---

## Node 1: Worktree Selection Advisor (Session Start)

**Trigger**: `SessionStart` hook fires when Claude begins

**Inputs**:
- `git worktree list --porcelain` — all worktrees
- `git log --oneline -5` per worktree — recent activity
- `.worktree-first/state.json` — last used worktree (if exists)
- `git diff --stat` — dirty/clean status

**AI Prompt Template**:
```
PURPOSE: Recommend which worktree to resume for this session; success = user lands in the most relevant context immediately
TASK: • Analyze all worktrees: branch name, last commit message, dirty/clean, checkpoint count, time since last activity • Factor recency (last-used worktree gets priority boost) • Factor urgency (dirty worktree that hasn't been checkpointed recently is higher risk)
MODE: analysis
CONTEXT: Worktrees: {worktree_list} | Last used: {last_used} | Current time: {now}
EXPECTED: One recommendation with reasoning: "Resume {name} because...". Include 1-sentence context summary of where work left off.
CONSTRAINTS: If no worktrees exist, output "start-new". If all worktrees are stale (>1 week inactive), note that.
```

**Script**: `ai-worktree-advisor.sh`
**Hook integration**: Run after `repo-status.sh` in `SessionStart`, before user sees the prompt.

---

## Node 2: Checkpoint Advisor (Pre-Checkpoint)

**Trigger**: User runs `/worktree-first:checkpoint` OR AI detects large staged diff

**Inputs**:
- `git diff --cached --stat` — staged diff size and file count
- `git log -1 --format="%s"` — last checkpoint message
- Time since last checkpoint (from state file)

**AI Prompt Template**:
```
PURPOSE: Assess whether current staged changes represent a meaningful checkpoint; success = checkpoint is created only at real intent boundaries
TASK: • Analyze staged diff: size (trivial <50 lines vs substantial), scope (single concern vs scattered), intent clarity • Check if last checkpoint was very recent (<10min ago) and similar scope — if so, suggest continuing • If diff is large (>500 lines) and touches multiple concerns, suggest splitting into multiple checkpoints
MODE: analysis
CONTEXT: Staged: {diff_stat} | Last checkpoint: {last_msg} ({time_ago}) | Checkpoint count this session: {count}
EXPECTED: One of: "checkpoint now ({reason})", "continue working ({reason})", "split first ({specific suggestion})"
CONSTRAINTS: Be conservative — prefer checkpoint if uncertain. Trivial mechanical changes (formatting, rename) should suggest "continue".
```

**Script**: `ai-checkpoint-advisor.sh`
**Integration**: Called at start of `checkpoint.sh` before `git commit`. If advisor says "continue", exit without committing.

---

## Node 3: Mid-Session Checkpoint Reminder (Proactive)

**Trigger**: Time-based polling (every 20-30 min of active editing) OR on significant diff accumulation

**Inputs**:
- Time since last checkpoint (from state file)
- `git diff --stat` — uncommitted changes size
- Session activity rate (files changed per minute, estimated)

**AI Prompt Template**:
```
PURPOSE: Determine if user should checkpoint now; success = no more than 45min of uncommitted work lost if crash
TASK: • Estimate risk: time since last checkpoint × current diff size • If >30min with >200 lines of uncommitted diff, recommend checkpoint • If <10min since last checkpoint, skip reminder regardless of diff
MODE: analysis
CONTEXT: Uncommitted: {diff_stat} | Time since last checkpoint: {minutes}m | Session started: {session_start}
EXPECTED: One of: "checkpoint reminder ({urgency})", "skip ({reason})"
CONSTRAINTS: Don't interrupt too frequently. Minimum 25min between reminders. Maximum 1 reminder per 20min of active editing.
```

**Script**: `ai-checkpoint-reminder.sh`
**Integration**: New hook `MidSession` or polling via `session-start-inject` check. Not blocking — outputs advisory message to user.

---

## Node 4: Push Readiness Assessor (Pre-Push)

**Trigger**: Before running `prepare-push.sh` or when user expresses intent to push

**Inputs**:
- `git diff origin/main..HEAD --stat` — full diff to be pushed
- `git log origin/main..HEAD --oneline` — commit history
- Test results from `prepare-push.sh` validation
- File count and type distribution

**AI Prompt Template**:
```
PURPOSE: Assess whether this branch is ready for code review; success = PR will be approved without rework cycles
TASK: • Analyze diff scope: focused (single concern) vs scattered (multiple unrelated changes) • Estimate review complexity: files changed, cyclomatic complexity changes, new dependencies • Check for common PR red flags: large diff without explanation, no tests, breaking changes not mentioned • Estimate risk level: LOW (small, focused, tested) vs MEDIUM vs HIGH (large, complex, untested)
MODE: analysis
CONTEXT: Diff: {diff_stat} | Commits: {commit_count} | Files: {file_types} | Tests: {test_status}
EXPECTED: Readiness score (1-5 stars). If <3 stars, list top 2-3 specific improvements before push. If >=3 stars, "Ready — proceed."
CONSTRAINTS: Be specific, not generic. "Add tests" is bad. "search-index module lacks test coverage for the new Tokenizer class" is good.
```

**Script**: `ai-push-readiness.sh`
**Integration**: Run at start of `prepare-push.sh` before rebase step. Output becomes part of the prepare-push UI.

---

## Node 5: Completion Readiness Check (Pre-Finish)

**Trigger**: Before `finish-task.sh` or when user tries to mark task complete

**Inputs**:
- All files modified in the branch
- `git log origin/main..HEAD` — full commit history
- TODO/FIXME/BUG comment scan in changed files
- Original task description (if captured in first commit message)

**AI Prompt Template**:
```
PURPOSE: Verify task is genuinely complete before cleanup; success = no forgotten items after worktree is deleted
TASK: • Scan changed files for incomplete markers: TODO, FIXME, BUG, HACK, XXX • Check if related files were modified (e.g., if you modified API, did you also update the API docs?) • Compare stated task goal (from first commit or branch name) vs actual changes • Look for obvious gaps: error handling added? Edge cases considered? Edge case tests?
MODE: analysis
CONTEXT: Branch: {branch} | Task goal: {goal_from_branch_name} | Files: {files} | Commits: {commit_messages}
EXPECTED: One of: "complete ({confidence}%)", "incomplete: missing {specific_items}", "almost done: consider {1-2 items}"
CONSTRAINTS: If incomplete, be specific about what. Don't block on style/nits — only substantive gaps.
```

**Script**: `ai-completion-check.sh`
**Integration**: Run in `finish-task.sh` before cleanup. If "incomplete", prompt user to confirm or address before deleting worktree.

---

## Node 6: Context Restorer (Session Resume)

**Trigger**: When resuming a worktree after a previous session

**Inputs**:
- `.worktree-first/sessions/{session_id}.json` — previous session history
- `git log -10 --format="%s"` — recent commits with checkpoint context
- `git diff HEAD~3..HEAD --stat` — recent changes
- Last checkpoint message

**AI Prompt Template**:
```
PURPOSE: Give the user immediate context on where they left off; success = user doesn't need to re-read code to remember what they were doing
TASK: • Identify the last meaningful checkpoint and what it achieved • Summarize the current state: what's been done, what's in progress, what's next • Note any unresolved questions or known issues from previous session
MODE: analysis
CONTEXT: Branch: {branch} | Last checkpoint: {last_checkpoint} | Recent commits: {commits} | Dirty files: {dirty_files}
EXPECTED: 3-sentence summary: "You were working on X. Last checkpoint: Y. Current state: Z."
CONSTRAINTS: Keep it brief — user needs orientation, not a full status report.
```

**Script**: `ai-context-restorer.sh`
**Integration**: Run immediately on session resume before any other context. Output becomes the first thing the user sees.

---

## Implementation Strategy

### Phase 1: Quick Wins (Low Effort, High Impact)
- **Node 1**: Worktree advisor — add to `SessionStart` via new script
- **Node 6**: Context restorer — add to `SessionStart` hook chain

### Phase 2: Core Loop (Medium Effort, High Value)
- **Node 2**: Checkpoint advisor — integrate into `checkpoint.sh`
- **Node 4**: Push readiness — integrate into `prepare-push.sh`

### Phase 3: Proactive (Higher Effort, Nice to Have)
- **Node 3**: Checkpoint reminder — time-based polling advisor
- **Node 5**: Completion check — integrate into `finish-task.sh`

---

## Technical Notes

### AI Tool Selection
- Use `ccw cli --tool gemini --mode analysis` for all advisor scripts
- Pass worktree context via `--cd` flag and `--includeDirs` for git repo access
- Keep prompts focused — one decision per invocation

### State File Requirements
All nodes read from `.worktree-first/state.json`:
```json
{
  "current_task": "search-index",
  "current_worktree": "/Users/x/proj/wt/search-index",
  "last_checkpoint": "2026-03-24T10:30:00Z",
  "checkpoint_count": 3,
  "session_history": [
    { "session_id": "abc", "start": "...", "end": "...", "checkpoints": 2 }
  ]
}
```

### Performance
- Advisor scripts should complete in <10s (use fast model if needed)
- Cache advisor output if same state hasn't changed
- Don't run advisors more than once per StateChange event
