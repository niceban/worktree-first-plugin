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
| `/worktree-first:start-task` | Create task branch + worktree from `origin/main` | No (user-only) |
| `/worktree-first:resume-task` | List active worktrees, pick up where you left off | Yes |
| `/worktree-first:checkpoint` | Create a local checkpoint commit after intent boundary | Yes (task worktree only) |
| `/worktree-first:prepare-push` | Rebase onto latest main, squash history, run full validation | Yes |
| `/worktree-first:prepare-pr` | Generate PR description from branch diff + commits | Yes |
| `/worktree-first:finish-task` | Remove worktree + delete branches after merge/abandon | No (user-only) |
| `/worktree-first:release-tag` | Tag from clean `main` after verified stable state | No (user-only) |
| `/worktree-first:doctor` | Audit all worktrees, flag orphaned/stale/dirty ones | Yes |

---

## Hooks (automatic, no manual trigger)

| Hook | What it does |
|------|-------------|
| `session-start-inject` | Prints branch, clean/dirty, worktree path, recent commits on every session start |
| `guard-main-write` | Blocks Edit/Write if on `main` or outside a task worktree |
| `guard-dangerous-bash` | Blocks dangerous commands: `git push -f main`, `git reset --hard`, `git clean -fdx`, bare `--force` |
| `post-edit-format` | Auto-runs format + whitespace check after every Edit/Write |
| `task-completed-gate` | Blocks TaskCompleted unless on task branch, clean, and not unpushed checkpoint |

---

## Core Rules

1. **Never edit/write on `main`**
2. **Every change starts with `/worktree-first:start-task`**
3. **Checkpoint frequently during development**
4. **Squash before first push** (`/worktree-first:prepare-push`)
5. **Only PR + squash merge enters `main`**
6. **Tag only from clean `main`**
7. **Clean up worktree immediately after merge or abandon**

---

## Quick Reference

```bash
# New task
/worktree-first:start-task feat search-index
cd ../wt/search-index && claude

# During development (in worktree)
/worktree-first:checkpoint

# Before push
/worktree-first:prepare-push
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

---

## Directory Structure

```
worktree-first-plugin/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   ├── start-task/SILL.md
│   ├── resume-task/SKILL.md
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
│   ├── guard-bash.sh
│   ├── post-edit-format.sh
│   ├── task-completed-check.sh
│   ├── start-task.sh
│   ├── resume-task.sh
│   ├── checkpoint.sh
│   ├── prepare-push.sh
│   ├── prepare-pr.sh
│   ├── finish-task.sh
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
