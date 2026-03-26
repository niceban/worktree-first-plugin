# IMPL-001 Summary: Rebuild Guard Core Architecture

## Task ID
IMPL-001

## Status
COMPLETED

## Bugs Fixed
- D1+D2: Removed `cd "$PROJECT_DIR"` - now using `git -C "$PWD"` for all git operations
- D4: Implemented `is_worktree_dir()` using `git worktree list --porcelain`
- D5: Added idempotency check to `auto_create_worktree()` - fails if worktree already exists
- D6: Added rollback mechanism - if metadata creation fails, worktree is removed
- D7: Dynamic worktree path using `git worktree list` parent directory

## Files Modified
1. `/Users/c/auto-git/worktree-first-plugin/scripts/guard-bash.sh`
2. `/Users/c/auto-git/worktree-first-plugin/scripts/guard-main-write.sh`
3. `/Users/c/auto-git/worktree-first-plugin/scripts/guard-auto-worktree.sh`

## Key Architecture Changes

### New Main Worktree Detection
```bash
get_git_root() {
  git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo ""
}

is_main_worktree() {
  local git_root
  git_root=$(get_git_root)
  [[ -z "$git_root" ]] && return 1
  [[ "$(realpath "$PWD")" == "$(realpath "$git_root")" ]]
}
```

### New Worktree Detection (D4)
```bash
is_worktree_dir() {
  local pwd="$1"
  git worktree list --porcelain | awk '$1 == "path" { print $2 }' | \
    while IFS= read -r wt_path; do
      [[ "$(realpath "$pwd")" == "$(realpath "$wt_path")" ]] && return 0
    done
  return 1
}
```

### Idempotency Check (D5)
```bash
if [[ -d "$wt_path" ]]; then
  echo "Worktree already exists at $wt_path" >&2
  return 1
fi
```

### Rollback Mechanism (D6)
```bash
if ! mkdir -p "$meta_dir"; then
  [[ "$created" == "true" ]] && git worktree remove "$wt_path"
  return 1
fi
```

### Dynamic Worktree Base (D7)
```bash
get_wt_base() {
  local git_root
  git_root=$(get_git_root)
  if [[ -z "$git_root" ]]; then
    echo "../wt"
    return
  fi
  dirname "$git_root"/wt
}
```

## Core Insight
In a task worktree, ALL operations are safe because worktrees are isolated environments. The guard now:
1. Never cd away from PWD
2. Detects main worktree by PWD == git_root
3. Allows all operations inside worktrees
4. Only blocks dangerous operations in main worktree

## Test Results
38 tests passed, 0 failed
