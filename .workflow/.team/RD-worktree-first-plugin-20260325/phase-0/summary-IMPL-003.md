# IMPL-003 Summary: hooks.json Update

## Task ID
IMPL-003

## Status
COMPLETED

## Changes Made

### Updated File
`/Users/c/auto-git/worktree-first-plugin/hooks/hooks.json`

### Key Changes

1. **Unified PreToolUse handlers**: Both `Edit|Write|MultiEdit` and `Bash` now point to `guard-auto-worktree.sh`
   - Before: Edit|Write|MultiEdit → guard-main-write.sh, Bash → guard-bash.sh
   - After: Both → guard-auto-worktree.sh

2. **Timeout increased to 15 seconds** (from 10)
   - Reason: worktree creation may take longer

3. **guard-main-write.sh and guard-bash.sh marked for deletion**
   - These are now superseded by guard-auto-worktree.sh
   - The files remain but are no longer referenced in hooks.json

## New hooks.json Structure

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/guard-auto-worktree.sh",
            "timeout": 15
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/guard-auto-worktree.sh",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

## Validation
- hooks.json is valid JSON
- guard-auto-worktree.sh is now the single handler for all dangerous operations
- Old scripts (guard-main-write.sh, guard-bash.sh) can be deleted in cleanup phase
