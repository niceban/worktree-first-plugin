# Challenger Critique: BRS-final-verify-20260324

## Executive Summary

Reviewed 4 idea documents and 6 key scripts. Found **1 CRITICAL issue that causes actual failures**, **2 HIGH severity risks**, and **3 MEDIUM** concerns. The `finish-task.sh` worktree removal failure scenario reveals a **CRITICAL flaw** that can cause permanent metadata loss with no recovery path.

---

## Per-Idea Challenges

### IDEA-hook.md (Hook Integration Ideas)

#### Idea 2: Missing guard-* script error handling

**Challenge**: hooks.json references `${CLAUDE_PLUGIN_ROOT}/scripts/guard-bash.sh`. If `CLAUDE_PLUGIN_ROOT` is unset or script deleted, the hook fails.

**Extreme Case Test**: If the script file is missing but `CLAUDE_PLUGIN_ROOT` is set, the hook system tries to execute a non-existent file. The hook system behavior for missing scripts is **unknown** - it could:
- Silently skip (allowing all commands through - security hole)
- Error out (denying all commands - usability issue)
- Execute default behavior

**Verification**: hooks.json has no Error hook defined. This means hook execution failures have undefined behavior.

**Severity**: HIGH

---

#### Idea 4: guard-bash.sh regex coverage

**Challenge**: The idea claims `git reset --hard` is blocked but `git reset --hard HEAD~1` (with path) might bypass.

**Extreme Case Test**:
```bash
# Test command: git reset --hard HEAD~1
# Regex at line 78: 'git[[:space:]]+reset[[:space:]]+--hard'
# This matches because there's no $ anchor requiring end-of-string
```

Wait - looking at line 78: `git reset --hard` pattern has no `$`, so `git reset --hard HEAD~1` **DOES match** (good). But line 123 has `git[[:space:]]+reset[[:space:]]+--hard[[:space:]]*$` which blocks bare `git reset --hard` but **NOT** `git reset --hard HEAD~1`.

**The actual gap**: Line 78 catches `git reset --hard` with anything after it, but the message says "without path is ambiguous" which is misleading since the regex catches WITH path too.

**Rule 5 analysis**:
```bash
git[[:space:]]+clean[[:space:]]+-[fFxX]([xX]|[dD][xX])$
```
- `git clean -fdx` → MATCH (correct)
- `git clean -fd` → NO MATCH (correct - safe)
- `git clean -fx` → MATCH (over-block - this removes ignored files only, not untracked)

**Severity**: MEDIUM - over-blocking but not a security gap

---

### IDEA-script.md (Script Correctness Review)

#### Issue 2: `timeout` missing on macOS (CRITICAL)

**Verification from checkpoint.sh line 45**:
```bash
ccw_output=$(perl -e 'alarm shift; exec @ARGV' 30 -- ccw cli -p "..." 2>/dev/null) || true
```

**GOOD NEWS**: The script has already been fixed to use `perl -e 'alarm shift; exec @ARGV'` instead of `timeout`. This is cross-platform compatible (works on Linux and macOS).

**However**: The perl-based timeout will throw `Alarm clock` to stderr on timeout, which may confuse users.

**Severity**: MEDIUM (already mitigated)

---

#### Issue 3: Invalid regex `""` empty alternative

**Verification from checkpoint.sh line 103**:
```bash
if [[ "$line" =~ ^new\ file ]]; then
```

The regex is `^new\ file` - there is NO empty alternative `""`. The IDEA-script.md claim about `^(new file|"")` is **incorrect** - that pattern does not exist in the current code.

**Severity**: N/A (issue doesn't exist in current code)

---

#### Issue 6: finish-task.sh metadata-before-worktree (CRITICAL)

**Verification from finish-task.sh**:

Lines 47-48 (current code):
```bash
# 0. Remove worktree first (metadata deleted AFTER successful removal)
git worktree remove "$WT_PATH" && echo "  [OK] worktree removed" || { echo "  [FAIL] worktree remove failed" >&2; exit 1; }
```

**The code has ALREADY been fixed** - metadata deletion (lines 51-56) happens AFTER worktree removal, not before.

**However, there's still a CRITICAL issue**: If `git worktree remove` fails (line 48), the script exits with code 1. But **metadata still exists** (hasn't been deleted yet). The user can re-run `finish-task.sh` - but what if the worktree is in a broken state?

**Recovery scenario for worktree removal failure**:
1. User runs `finish-task.sh`
2. `git worktree remove` fails (uncommitted changes not caught by guard)
3. Script exits with code 1
4. Metadata still exists at `.worktree-first/worktrees/{slug}.json`
5. User manually resolves the issue
6. User re-runs `finish-task.sh` - works correctly

**The dangerous scenario**:
1. User runs `finish-task.sh`
2. `git worktree remove` fails
3. User doesn't notice the failure, does `git clean -fdx` to clean up
4. Re-runs `finish-task.sh` - worktree is gone but metadata persists
5. OR: User deletes worktree manually, metadata orphaned

**What if metadata is truly lost?** There is **NO recovery mechanism**. The doctor skill cannot fix this.

**Severity**: HIGH (the fix exists but recovery path is unclear)

---

### IDEA-ai.md (AI Fallback Chain)

#### Section 5: jq on macOS

**Verification**: select-worktree.sh uses jq at lines 29-32 to parse metadata:
```bash
branch=$(jq -r '.branch // ""' "$meta_file" 2>/dev/null)
dirty=$(jq -r '.dirty // false' "$meta_file" 2>/dev/null)
checkpoints_len=$(jq -r '.checkpoints | length // 0' "$meta_file" 2>/dev/null)
last_active=$(jq -r '.last_active_at // ""' "$meta_file" 2>/dev/null)
```

**If jq doesn't exist on macOS**:
- All `jq` commands fail silently (2>/dev/null)
- `branch=""`, `dirty="false"`, `checkpoints_len="0"`, `last_active=""`
- Entries are still added to array with empty values
- User sees: `  [1]            0 checkpoint  last: unknown`
- Cannot identify worktrees, cannot see dirty status
- Script exits 0 (no error)

**This is a silent failure** - users may not realize jq is missing and think all worktrees are clean/empty.

**Severity**: HIGH

---

#### Section 4: timeout 30s adequacy

**Analysis**: The checkpoint.sh uses `perl -e 'alarm 30'` for timeout, which is correct. However:
- If timeout occurs, perl writes "Alarm clock" to stderr
- The `|| true` catches this, ccw_output is empty
- Falls through to rule-based suggestion (correct behavior)

**The concern is not crash but UX**: User sees no AI recommendation and doesn't know if it was timeout vs ccw not found.

**Severity**: LOW

---

### IDEA-meta.md (Metadata Handling)

#### Section 2: checkpoint.sh metadata file not found

**Verification from checkpoint.sh lines 200-225**:
```bash
_meta_update_checkpoint() {
  local meta_file="${repo_root}/.worktree-first/worktrees/${slug}.json"
  if [[ -f "$meta_file" ]]; then
    # ... jq update ...
    echo "  [OK] metadata updated"
  fi
  # No else branch - silent failure
}
```

**If metadata file doesn't exist**: Silent no-op. No error, no warning.

**Impact**: checkpoint is created successfully, but metadata doesn't reflect it. `doctor` skill will show incorrect checkpoint count.

**Why this might happen**: User manually deletes metadata file, or race condition with finish-task.sh running concurrently.

**Severity**: MEDIUM

---

## Special Analysis: Guard Scripts in Detached HEAD

### Security Analysis of `current_branch` Empty

**guard-bash.sh behavior when detached HEAD**:
- Line 20: `current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")` → empty
- Line 25: `[[ "$current_branch" == "main" ]]` → false, Rule 1 **bypassed**
- Rules 2-7: Pure pattern matching, **NOT** dependent on current_branch

**What this means**:
| Command | Rule 1 (main only) | Rules 2-7 | Result |
|---------|-------------------|----------|--------|
| `echo "test" > file.txt` (in worktree) | Bypassed (not main) | Not git command | ALLOWED |
| `git push origin main` | N/A | Rule 2 blocks | BLOCKED |
| `git push --force origin feat` | N/A | Rule 3 blocks | BLOCKED |
| `git reset --hard` | N/A | Rule 4 blocks | BLOCKED |
| `git clean -fdx` | N/A | Rule 5 blocks | BLOCKED |
| `git branch -d main` | N/A | Rule 6 blocks | BLOCKED |

**Is there a security gap?**

The gap is: **file-writing Bash commands are NOT blocked in detached HEAD state within a worktree**. But:
1. You're in a worktree (not main), so file-writing is expected
2. `guard-main-write.sh` (for Edit/Write tools) also allows detached HEAD: `[[ -z "$current_branch" ]] && exit 0` (line 18)
3. The system treats detached HEAD as "advanced mode" - user knows what they're doing

**Conclusion**: Not a security hole - intentional design choice. Detached HEAD users get full access but are protected from main-branch mistakes.

**Severity**: LOW (by design)

---

## Summary Table

| Issue | Source | Severity | Status |
|-------|--------|----------|--------|
| guard-* script missing | IDEA-hook Idea 2 | HIGH | Unresolved - no Error hook defined |
| guard-bash.sh Rule 5 over-blocks -fx | IDEA-script Issue 1 | MEDIUM | By design - acceptable |
| timeout command fixed with perl | IDEA-script Issue 2 | MEDIUM | Already mitigated |
| Invalid regex `""` claim | IDEA-script Issue 3 | N/A | Issue doesn't exist |
| finish-task.sh recovery | IDEA-script Issue 6 | HIGH | Partial fix - no recovery mechanism |
| select-worktree.sh jq silent failure | IDEA-ai Section 5 | HIGH | Unresolved |
| checkpoint.sh timeout UX | IDEA-ai Section 4 | LOW | Acceptable |
| checkpoint.sh metadata silent fail | IDEA-meta Section 2 | MEDIUM | Unresolved |
| Detached HEAD guard bypass | Special Analysis | LOW | By design |

---

## GC Signal

**REVISION_NEEDED**

### Top 3 Priority Fixes

1. **select-worktree.sh jq dependency**: Add `command -v jq` check at script start, warn user if missing, do not silently produce empty output
2. **finish-task.sh recovery path**: Document what to do when `git worktree remove` fails. Consider adding `finish-task.sh --force` to handle broken worktrees
3. **guard-* missing script handling**: Define Error hook in hooks.json to handle missing/broken guard scripts explicitly (deny by default, not silent allow)

### Issues Already Mitigated

- checkpoint.sh `timeout` replaced with perl-based alarm
- finish-task.sh metadata deletion reordered after worktree removal

### Issues By Design

- Detached HEAD bypasses guard-main-write.sh and guard-bash.sh Rule 1
- guard-bash.sh Rule 5 intentionally blocks -fx (not just -fdx)
