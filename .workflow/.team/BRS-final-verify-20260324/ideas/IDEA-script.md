# Script Correctness Review: Worktree-First Plugin

**Topic**: 真的可用了么？对我这个插件做最严格的逐行审查
**Angles**: script_correctness, hook_integration, ai_fallback_chain, metadata_integrity
**Mode**: Initial Generation
**Round**: 0

---

## Executive Summary

Analyzed 7 shell scripts for correctness, variable passing, regex behavior, and runtime errors. Found **5 critical issues** that will cause actual failures, **3 potential issues**, and several edge cases requiring attention.

---

## 1. guard-bash.sh — Line-by-Line Analysis

### Variable Passing
| Line | Variable | Analysis |
|------|----------|----------|
| 10 | `input=$(cat)` | Reads entire stdin into variable. OK. |
| 11 | `COMMAND=$(echo "$input" \| jq -r ...)` | Extracts .tool_input.command. OK if JSON structure matches. |
| 15 | `PROJECT_DIR` | Uses parameter expansion with fallback. OK. |
| 20 | `current_branch` | Captured from git symbolic-ref. Could be empty on detached HEAD. |
| 29 | Regex patterns | Uses ERE `grep -qE`. All verified working on macOS. |
| 47 | `git[[:space:]]+push...` | Regex alternation works correctly. |

### Verified Regex Behavior (macOS grep -E)

| Pattern | Test Case | Result |
|---------|-----------|--------|
| Rule 1: `(\s>>\|\s>...)` | `echo "hello > file.txt"` | MATCH |
| Rule 1 exception | `echo "test >/dev/null"` | NO MATCH (correct) |
| Rule 2: `git push...main` | `git push origin main` | MATCH |
| Rule 2: refs/heads | `git push origin refs/heads/main` | MATCH |
| Rule 3: --force | `git push --force origin feat` | MATCH |
| Rule 3 exception | `git push --force-with-lease` | NO MATCH (correct) |
| Rule 4: reset --hard | `git reset --hard` | MATCH |
| Rule 5: clean -fdx | `git clean -fdx` | MATCH |
| Rule 5: clean -fd | `git clean -fd` | NO MATCH (correct) |
| Rule 5: clean -fx | `git clean -fx` | MATCH (more aggressive than comment suggests) |
| Rule 6: branch delete | `git branch -d main` | MATCH |
| Rule 7: reset --hard$ | `git reset --hard ` (trailing space) | MATCH |

### Issues Found

**Issue #1 (CRITICAL) — Rule 5 Regex Over-Broad**
- **Location**: Line 93
- **Pattern**: `git[[:space:]]+clean[[:space:]]+-[fFxX]([xX]|[dD][xX])$`
- **Problem**: The regex blocks `-fx` and `-fX` in addition to `-fdx`. The denial message only mentions `-fdx`.
- **Impact**: Scripts using `git clean -fx` (remove ignored files) will be incorrectly blocked.
- **Recommendation**: Change to specifically match `-fdx` variant only: `git[[:space:]]+clean[[:space:]]+-f[dD]?[xX]$` or clarify in comment that -fx is intentionally blocked.

---

## 2. checkpoint.sh — Line-by-Line Analysis

### Variable Passing
| Line | Variable | Analysis |
|------|----------|----------|
| 6 | `PROJECT_DIR` | OK with fallback. |
| 12 | `WORKTREE_PATH` | Derived from git rev-parse. Correctly identifies current worktree. |
| 15 | `WORKTREE_SLUG` | basename of path. OK. |
| 36 | `diff_content` | Captured from git diff --cached. OK. |
| 90-136 | `_generate_suggestion()` | Uses bash variables `changes`, `prefixes`. Scope is function-local. OK. |
| 145 | `ai_out_file` | Uses mktemp. Properly cleaned up. OK. |
| 203 | `slug` | Uses basename. Same as line 15. OK. |
| 207 | `repo_root` | `"$(git rev-parse --git-dir)/.."` - works from both main repo and worktree. |
| 211 | `now` | Uses `date -u +%Y-%m-%dT%H:%M:%SZ`. Works on macOS. |

### Issues Found

**Issue #2 (CRITICAL) — `timeout` Command Missing on macOS**
- **Location**: Line 44
- **Code**: `timeout 30 ccw cli -p "..." --tool gemini --mode write`
- **Problem**: The `timeout` command does not exist on macOS by default. This causes the entire `_ai_advisor()` function to fail immediately.
- **Impact**: AI checkpoint advisor completely unavailable on macOS. Falls back to rule-based suggestion but prints error message.
- **Recommendation**: Replace with bash built-in timeout or platform-specific alternative:
```bash
# macOS fallback using perl
if command -v timeout &>/dev/null; then
  ccw_output=$(timeout 30 ccw cli -p "$prompt" ...)
else
  # Use perl-based timeout as fallback
  ccw_output=$(perl -e 'alarm 30; exec @ARGV' ccw cli -p "$prompt" ...) 2>/dev/null || true
fi
```

**Issue #3 (HIGH) — Invalid Regex Causes Error Messages**
- **Location**: Line 102
- **Code**: `if [[ "$line" =~ ^(new file|"") ]]; then`
- **Problem**: The regex `^(new file|"")` contains an empty alternative `""` which is invalid in bash ERE. This prints "failed to compile regex" to stderr for every empty line.
- **Impact**: Every empty line in git diff --stat output generates an error. While not fatal (due to `|| echo ""`), it pollutes stderr.
- **Recommendation**: Remove the empty alternative:
```bash
if [[ "$line" =~ ^new\ file ]]; then
  changes+="add "
fi
```

**Issue #4 (MEDIUM) — jq Dependency Not Checked Before Use**
- **Location**: Line 213
- **Problem**: Uses `jq` for metadata update but doesn't check if jq exists before line 213. However, the `_meta_update_checkpoint()` function is called at line 225 after all validation.
- **Impact**: If jq is missing, metadata update silently fails (jq errors go to /dev/null on line 213).
- **Recommendation**: Add jq availability check in `_meta_update_checkpoint()`.

**Issue #5 (LOW) — Syntax Check Runs on ALL Committed Files**
- **Location**: Line 228
- **Code**: `for file in $(git diff --name-only HEAD~1..HEAD)`
- **Problem**: If a commit contains 100 shell scripts, each gets bash -n syntax check. This could be slow.
- **Impact**: Minor performance consideration.
- **Recommendation**: Consider limiting to first N files or only files modified in last N commits.

---

## 3. prepare-push.sh — Line-by-Line Analysis

### Variable Passing
| Line | Variable | Analysis |
|------|----------|----------|
| 34 | `PRE_REBASE_REF` | Captured before rebase. Used for nothing afterward. Dead code. |
| 46 | `commit_count` | `wc -l \| tr -d ' '` correctly removes whitespace. OK. |
| 101 | `slug` | Same pattern as checkpoint.sh. OK. |
| 156 | `assessment` | Captures ccw output. OK. |
| 175 | Regex `STAR_RATING:\ ([0-5])/5` | Verified working. |

### Issues Found

**Issue #6 (LOW) — PRE_REBASE_REF Captured but Never Used**
- **Location**: Line 34
- **Code**: `PRE_REBASE_REF=$(git rev-parse HEAD)` before rebase
- **Problem**: The variable is set but never referenced afterward. Dead code.
- **Impact**: Minor dead code. Could be used for rollback reference if rebase fails.

**Issue #7 (LOW) — AI Assessment Regex Captures but Doesn't Validate Properly**
- **Location**: Line 175
- **Code**: `if [[ "$assessment" =~ STAR_RATING:\ ([0-5])/5 ]]; then`
- **Problem**: The regex uses `([0-5])` which in ERE means "match one character: 0, 1, 2, 3, 4, or 5". This is correct but could be written as `[0-5]` without parentheses.
- **Impact**: Minor style issue. Functionally correct.

---

## 4. start-task.sh — Line-by-Line Analysis

### Variable Passing
| Line | Variable | Analysis |
|------|----------|----------|
| 7-8 | `TYPE`, `SLUG` | Positional parameters. OK. |
| 26 | `BRANCH_NAME` | Constructed as `task/${TYPE}-${SLUG}`. Could contain invalid chars if SLUG is malformed. |
| 27 | `WT_PATH="../wt/${SLUG}"` | Relative path. OK but depends on current directory. |
| 28-29 | `WT_DIR`, `WT_META` | Derived from REPO_DIR. OK. |
| 31 | `cd "$REPO_DIR"` | Changes directory. All subsequent operations relative to this. |
| 84 | `$(realpath "$WT_PATH")` | realpath exists on macOS. OK. |

### Issues Found

**Issue #8 (HIGH) — No Validation of SLUG Format**
- **Location**: Lines 7-8, 25
- **Problem**: SLUG is used directly in branch name and path without validation. Invalid characters (spaces, special chars) could cause git failures.
- **Impact**: `start-task.sh feat "my task"` (with space) would create `task/feat-my task` which is invalid.
- **Recommendation**: Add slug validation:
```bash
if [[ ! "$SLUG" =~ ^[a-z0-9-]+$ ]]; then
  echo "Invalid slug: $SLUG. Use kebab-case (a-z, 0-9, -)." >&2
  exit 1
fi
```

**Issue #9 (MEDIUM) — WT_PATH Relative to Current Directory**
- **Location**: Line 27
- **Code**: `WT_PATH="../wt/${SLUG}"`
- **Problem**: Relative path depends on current working directory. If script is run from different location, worktree could be created elsewhere.
- **Impact**: Worktree might be created in unexpected location.
- **Recommendation**: Use absolute path or ensure cd to REPO_DIR happens before WT_PATH assignment.

---

## 5. resume-task.sh — Line-by-Line Analysis

### Variable Passing
| Line | Variable | Analysis |
|------|----------|----------|
| 6 | `REPO_DIR` | OK with fallback. |
| 11 | `git worktree list --porcelain` | Outputs null-byte separated fields. |
| 17 | `slug=$(basename "$path")` | Extracts slug correctly. |
| 39 | `ahead=$(git log... | wc -l)` | Captures ahead count. OK. |

### Issues Found

**Issue #10 (LOW) — Broken Pipe Handling in while loop**
- **Location**: Lines 11-35
- **Problem**: The `while read -r line` loop reads from `git worktree list --porcelain`. If the command produces many lines, a broken pipe warning could appear if `head` is used downstream.
- **Impact**: Minor cosmetic issue.
- **Recommendation**: Add `2>/dev/null` to suppress potential warnings.

**Issue #11 (LOW) — Unpushed Branch Check Uses Wrong Direction**
- **Location**: Line 40
- **Code**: `git log origin/main.."origin/$branch"`
- **Problem**: This shows commits in `origin/$branch` not in `origin/main`. But `origin/$branch` might not exist yet if never pushed.
- **Impact**: Shows "0 unpushed" for new branches even though local commits exist.
- **Recommendation**: Check if origin/$branch exists first, or check local-only commits.

---

## 6. finish-task.sh — Line-by-Line Analysis

### Variable Passing
| Line | Variable | Analysis |
|------|----------|----------|
| 7 | `WT_PATH="$PWD"` | Captures worktree path BEFORE any cd. Critical correctness. |
| 12 | `REPO_DIR` | Uses `$(cd "$(git rev-parse --git-dir)/.." && pwd)`. Works correctly. |
| 34 | Git status checks | Uses `git diff --quiet`. OK. |

### Issues Found

**Issue #12 (HIGH) — Worktree Remove Fails Silently Without Cleanup**
- **Location**: Line 56
- **Code**: `git worktree remove "$WT_PATH" && echo "[OK]" || echo "[FAIL]"`
- **Problem**: If `git worktree remove` fails (e.g., worktree has uncommitted changes not detected earlier), the metadata file is already deleted (line 50) and local branch might be deleted (line 60). This leaves inconsistent state.
- **Impact**: Metadata gone but worktree still exists. Local branch might be partially deleted.
- **Recommendation**: Delete metadata AFTER successful worktree removal, not before:
```bash
# 1. Remove worktree first
git worktree remove "$WT_PATH" || { echo "[FAIL] worktree remove"; exit 1; }
# 2. Delete branch
git branch -d "$branch"
# 3. Delete remote
git push origin --delete "$branch"
# 4. ONLY delete metadata after all steps succeed
rm -f "$META_FILE"
```

---

## 7. select-worktree.sh — Line-by-Line Analysis

### Variable Passing
| Line | Variable | Analysis |
|------|----------|----------|
| 6 | `REPO_DIR` | Uses CLAUDE_PROJECT_DIR fallback. OK. |
| 27 | `while IFS= read -r -d ''` | Reads null-byte terminated entries. Correct. |
| 36-40 | `last_rel` calculation | Uses platform-specific date commands. Correctly handles macOS vs Linux. |
| 61 | `sort -z` | Sorts null-byte terminated input. Correct. |
| 98 | `user_input =~ ^[0-9]+$` | Validates numeric input. OK. |

### Issues Found

**Issue #13 (LOW) — Array Index Off-By-One in User Selection**
- **Location**: Lines 100-102
- **Code**: `entry="${entries[$((user_num - 1))]}"`
- **Problem**: If user enters 0 (which matches `^[0-9]+$`), then `user_num - 1 = -1` which in bash is the last element of the array. This allows selecting "0" as an index.
- **Impact**: User input "0" selects last worktree instead of erroring.
- **Recommendation**: Validate user_num >= 1 explicitly.

**Issue #14 (LOW) — Race Condition in Metadata Reading**
- **Location**: Lines 28-32
- **Problem**: Reads metadata files with jq but doesn't handle concurrent writes.
- **Impact**: If another process updates metadata while this script runs, reads could get partial data.
- **Impact**: Low risk in practice. Acknowledged as acceptable tradeoff.

---

## Summary of Critical Issues

| # | Script | Issue | Severity |
|---|--------|-------|----------|
| 1 | guard-bash.sh | Rule 5 regex over-broad (blocks -fx) | MEDIUM |
| 2 | checkpoint.sh | `timeout` missing on macOS | CRITICAL |
| 3 | checkpoint.sh | Invalid regex `""` empty alternative | HIGH |
| 4 | checkpoint.sh | jq availability not checked | MEDIUM |
| 5 | start-task.sh | No slug validation | HIGH |
| 6 | finish-task.sh | Metadata deleted before worktree removal | HIGH |
| 7 | select-worktree.sh | Array index off-by-one | LOW |

---

## Recommendations Priority

### Must Fix (Before Production)
1. **checkpoint.sh**: Replace `timeout` with macOS-compatible alternative
2. **start-task.sh**: Add slug format validation
3. **finish-task.sh**: Reorder operations to delete metadata last
4. **checkpoint.sh**: Fix invalid regex `""` pattern

### Should Fix
5. **guard-bash.sh**: Clarify or adjust Rule 5 regex scope
6. **checkpoint.sh**: Check jq availability before use

### Nice to Have
7. **prepare-push.sh**: Remove dead code PRE_REBASE_REF
8. **resume-task.sh**: Fix unpushed branch direction logic
9. **select-worktree.sh**: Fix array index validation
