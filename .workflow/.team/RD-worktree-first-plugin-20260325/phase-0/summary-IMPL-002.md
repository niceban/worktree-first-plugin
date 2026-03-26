# IMPL-002 Summary: guard-auto-worktree.sh Complete Implementation

## Task ID
IMPL-002

## Status
COMPLETED

## Description
Implemented complete guard-auto-worktree.sh with suggestion + 7 danger rules

## Features Implemented

### 7 Danger Rules
1. **Rule 1**: File-writing commands (`>`, `>>`, `tee`, `sed -i`, `perl -i`, etc.)
2. **Rule 2**: git push to main (any form)
3. **Rule 3**: bare --force (without --force-with-lease)
4. **Rule 3b**: -f short form
5. **Rule 4**: git reset --hard (bare form)
6. **Rule 5**: git clean -x or -X
7. **Rule 6**: delete main/master branch

### Suggestion Format
When dangerous operation detected in main worktree, returns:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Auto-created worktree at <path>. Switch to it with: cd <path>, then retry your edit.",
    "suggestions": [
      {
        "description": "Switch to worktree and continue",
        "action": "bash",
        "command": "cd <path> && echo \"Switched to worktree. You can now edit files.\""
      }
    ]
  }
}
```

### Core Behavior
- **In main worktree (PWD == git root)**:
  - Write operations (Edit/Write/MultiEdit): auto-create worktree + deny + suggestion
  - Dangerous Bash: auto-create worktree + deny + suggestion
  - Non-dangerous operations: allow

- **In worktree (PWD != git root)**:
  - ALL operations: allow (worktree is isolated)

## File
`/Users/c/auto-git/worktree-first-plugin/scripts/guard-auto-worktree.sh`

## Test Results
Manual verification successful - worktree created and JSON response returned correctly
