# Worktree-First Plugin

Enforces branch + worktree isolation for all changes. Claude works only inside task worktrees. main stays clean. History is clean before push.

## Installation

### Local Dev / Trial

```bash
git clone <repo-url>
cd worktree-first-plugin
claude --plugin-dir .
```

### Marketplace Install

```bash
/plugin marketplace add <owner>/<repo>
/plugin install worktree-first@<marketplace>
```

Choose scope:
- **Project** — team-shared, saved to `.claude/settings.json` (recommended for this plugin)
- **User** — your全局, saved to `~/.claude/settings.json`
- **Local** — current session only

---

## Skills

| Skill | Purpose | Auto-run |
|-------|---------|----------|
| `/worktree-first:select-worktree` | Interactive worktree selector at session start | **Yes (SessionStart hook)** |
| `/worktree-first:start-task` | Create task branch + worktree from `origin/main` | No (user-only) |
| `/worktree-first:resume-task` | List active worktrees, pick up where you left off | Yes |
| `/worktree-first:checkpoint` | Create a local checkpoint commit after intent boundary | Yes (task worktree only) |
| `/worktree-first:prepare-push` | Rebase onto latest main, squash history, run AI readiness + validation | Yes |
| `/worktree-first:prepare-pr` | Generate PR description from branch diff + commits | Yes |
| `/worktree-first:finish-task` | Remove worktree + delete branches after merge/abandon | No (user-only) |
| `/worktree-first:release-tag` | Tag from clean `main` after verified stable state | No (user-only) |
| `/worktree-first:doctor` | Audit all worktrees, flag orphaned/stale/dirty ones | Yes |

---

## Hooks (automatic, no manual trigger)

| Hook | What it does |
|------|-------------|
| `session-start-inject` | Prints branch, clean/dirty, worktree path, recent commits on every session start |
| `session-start-select` | **NEW** — Runs `select-worktree.sh` interactively on SessionStart to offer worktree selection before coding begins |
| `guard-main-write` | Blocks Edit/Write if on `main` or outside a task worktree |
| `guard-dangerous-bash` | Blocks dangerous commands: `git push -f main`, `git reset --hard` (no path), `git clean -fdx`, bare `--force`, branch deletion of main/master |
| `post-edit-format` | Auto-runs format + whitespace check after every Edit/Write |
| `task-completed-gate` | Blocks TaskCompleted unless on task branch, clean, and not unpushed checkpoint |

---

## Core Rules

1. **Never edit/write on `main`**
2. **Session entry = `/worktree-first:select-worktree`** — pick existing or start new; this is the entry point, not `start-task`
3. **Every new task starts with `/worktree-first:start-task`**
4. **Checkpoint frequently during development** — AI advisor suggests commit-worthy moments
5. **Squash before first push** (`/worktree-first:prepare-push`) — AI gives push readiness rating first
6. **Only PR + squash merge enters `main`**
7. **Tag only from clean `main`**
8. **Clean up worktree immediately after merge or abandon**

---

## Quick Reference

```bash
# Session entry — interactive worktree selector (auto-runs on SessionStart)
/worktree-first:select-worktree

# New task (if select-worktree didn't offer what you need)
/worktree-first:start-task feat search-index
cd ../wt/search-index && claude

# During development (in worktree)
/worktree-first:checkpoint
# → AI advisor analyzes staged diff and suggests commit-worthy changes

# Before push
/worktree-first:prepare-push
# → AI gives push readiness rating (1-5 stars) before validation
# confirm push when ready

# After PR merged
/worktree-first:finish-task merged

# Audit
/worktree-first:doctor

# Tag from main
/worktree-first:release-tag v1.2.0 release
git push --tags
```

---

## Requirements

- Git 2.23+ (for `git worktree` commands)
- GitHub CLI (`gh`) optional (for PR creation in `prepare-pr`)
- Formatters/linters detected automatically if present (`make format`, `prettier`, `black`, `gofmt`)
- `ccw cli` (for AI advisor and AI push readiness features — falls back gracefully if unavailable)

---

## Metadata Storage

Each worktree has a `.worktree-first/worktrees/<slug>.json` metadata file tracking:

```json
{
  "slug": "auth-fix",
  "branch": "task/fix-auth-timeout",
  "worktree": "/path/to/wt/auth-fix",
  "status": "active",
  "dirty": false,
  "created_at": "2026-03-24T10:00:00Z",
  "last_active_at": "2026-03-24T15:30:00Z",
  "checkpoints": 5,
  "last_checkpoint_message": "checkpoint: auth timeout handler passes tests"
}
```

Scripts update metadata automatically on every state change (checkpoint, prepare-push, finish-task).

---

## AI Features (P2)

Two AI-powered features use `ccw cli --tool gemini --mode analysis` with graceful fallback:

| Feature | What it does |
|---------|-------------|
| **AI Checkpoint Advisor** | Before each checkpoint, analyzes staged diff and says whether it's commit-worthy + suggests a message. Falls back to rule-based suggestion on failure. |
| **AI Push Readiness** | Before validation, rates the branch 1–5 stars with a reason and improvement tips. Skipped (not blocking) if LLM unavailable. |

---

## Directory Structure

```
worktree-first-plugin/
├── .claude-plugin/
│   └── plugin.json
├── .worktree-first/                    # NEW: metadata storage
│   └── worktrees/
│       └── <slug>.json                 # per-worktree state (status, checkpoints, dirty)
├── skills/
│   ├── start-task/SKILL.md
│   ├── resume-task/SKILL.md
│   ├── select-worktree/SKILL.md        # NEW: interactive worktree selector
│   ├── checkpoint/SKILL.md
│   ├── prepare-push/SKILL.md
│   ├── prepare-pr/SKILL.md
│   ├── finish-task/SKILL.md
│   ├── release-tag/SKILL.md
│   └── doctor/SKILL.md
├── hooks/
│   └── hooks.json
├── scripts/
│   ├── repo-status.sh
│   ├── guard-main-write.sh
│   ├── guard-bash.sh                   # blocks 7 dangerous command patterns
│   ├── post-edit-format.sh
│   ├── task-completed-check.sh
│   ├── start-task.sh                   # idempotent (detects existing worktree)
│   ├── resume-task.sh                  # reads metadata for richer display
│   ├── select-worktree.sh              # NEW: interactive selector
│   ├── checkpoint.sh                   # AI advisor + rule-based message suggestion
│   ├── prepare-push.sh                 # AI readiness rating + rebase rollback
│   ├── prepare-pr.sh
│   ├── finish-task.sh                 # cleans up metadata on removal
│   ├── release-tag.sh
│   └── doctor.sh
└── README.md
```

---

## Uninstall

```bash
# Remove from project
# Edit .claude/settings.json and remove the plugin entry

# Or from user scope
/plugin uninstall worktree-first
```
