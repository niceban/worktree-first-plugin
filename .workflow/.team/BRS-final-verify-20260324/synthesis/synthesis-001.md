# Synthesis: Worktree-First Plugin Final Verification

**Session**: BRS-final-verify-20260324
**Synthesized**: 2026-03-25
**Input Sources**: IDEA-script.md, IDEA-hook.md, IDEA-ai.md, IDEA-meta.md, critique-001.md

---

## 1. Input Summary

| Source | Document | Key Focus |
|--------|----------|-----------|
| IDEA-script.md | Script Correctness Review | 7 shell scripts, line-by-line analysis, regex behavior, runtime errors |
| IDEA-hook.md | Hook Integration Ideas | 12 ideas covering async semantics, guard failures, skill interactions |
| IDEA-ai.md | AI Fallback Chain Analysis | ccw cli fallback, LLM output handling, jq dependency, timeout behavior |
| IDEA-meta.md | Metadata Integrity Analysis | metadata CRUD operations, git rev-parse behavior, slug extraction |
| critique-001.md | Challenger Critique | Verified/contradicted prior findings, recovery paths, severity recalibration |

---

## 2. Complete Issue List (All Severities)

### BLOCKER Issues (Cause actual failures / security holes)

| ID | Source | Issue | Status |
|----|--------|-------|--------|
| B1 | IDEA-hook / critique | **guard-* 脚本缺失时静默失败** - hooks.json references scripts via `${CLAUDE_PLUGIN_ROOT}`. If variable unset or script deleted, behavior is undefined (skip? error? allow-all?). No Error hook defined. Security mechanism can be bypassed silently. | **UNRESOLVED** |
| B2 | IDEA-hook / critique | **disable-model-invocation 无法阻止用户主动调用 skill** - start-task, release-tag, finish-task set `disable-model-invocation: true`, but users can directly invoke `/worktree-first:start-task`. PreToolUse hook behavior for skill-triggered commands is unverified. | **UNRESOLVED** |
| B3 | IDEA-hook / critique | **select-worktree.sh jq 静默失败** - On macOS (jq not default), all jq commands fail silently (2>/dev/null). User sees empty worktree list with exit 0. Cannot identify worktrees, cannot see dirty status. | **UNRESOLVED** |

### HIGH Severity Issues

| ID | Source | Issue | Status |
|----|--------|-------|--------|
| H1 | IDEA-script | **start-task.sh 无 slug 格式验证** - SLUG used in branch name and path without validation. Spaces/special chars cause git failures. | **UNRESOLVED** |
| H2 | IDEA-script / critique | **finish-task.sh worktree remove 失败后无恢复机制** - Metadata deletion reordered after removal (fixed), BUT if `git worktree remove` fails, no recovery path exists. Metadata orphaned if user manually cleans up. | **PARTIAL** - Ordering fixed, recovery undefined |
| H3 | IDEA-script | **checkpoint.sh jq 依赖未检查** - Uses jq for metadata update but no availability check. Silent failure leaves metadata stale. | **UNRESOLVED** |
| H4 | IDEA-hook | **hooks.json 缺少 Error/Exception hook** - No handling for guard script errors or timeouts. Assumption: errors = allow (security risk). | **UNRESOLVED** |
| H5 | IDEA-ai | **jq 缺失导致 metadata update 静默失败** - `_meta_update_checkpoint()` silently fails if jq missing. User unaware checkpoint not recorded. | **UNRESOLVED** |
| H6 | IDEA-hook | **SessionStart async=true 语义不明确** - select-worktree.sh uses `read -r user_input` for interactive selection. If async=true means "background/non-blocking", user cannot complete input. | **UNRESOLVED** |

### MEDIUM Severity Issues

| ID | Source | Issue | Status |
|----|--------|-------|--------|
| M1 | IDEA-script | **guard-bash.sh Rule 5 regex over-broad** - Blocks `-fx` in addition to `-fdx`. Message only mentions `-fdx`. | **BY DESIGN** (acceptable) |
| M2 | IDEA-script | **checkpoint.sh timeout 命令已修复** - Uses `perl -e 'alarm 30'` instead of `timeout`. Already mitigated per critique. | **MITIGATED** |
| M3 | IDEA-script | **Invalid regex `""` claim** - IDEA-script.md claimed `^(new file|"")` existed. Critique verified it does NOT exist in current code. | **DOES NOT EXIST** |
| M4 | IDEA-script | **start-task.sh WT_PATH 相对路径** - `../wt/${SLUG}` depends on current directory. Could create worktree in wrong location. | **UNRESOLVED** |
| M5 | IDEA-hook | **PostToolUse async=true 竞态条件** - post-edit-format.sh runs formatter async. Git diff may race with formatting completion. | **UNRESOLVED** |
| M6 | IDEA-hook | **task-completed-check.sh timeout 15s 可能不足** - Network slow or repo large时可能超时。 | **UNRESOLVED** |
| M7 | IDEA-hook | **select-worktree skill 与 SessionStart hook 功能重叠** - Both show worktree list. Hook auto-output may interfere with user's session. | **UNRESOLVED** |
| M8 | IDEA-hook | **guard 脚本 deny 格式不一致风险** - `exit 0 + JSON` convention not documented. Future scripts may use different format. | **UNRESOLVED** |
| M9 | IDEA-hook | **缺少 hook 集成测试** - No automated tests verify hooks.json loading, guard deny/allow, async semantics. | **UNRESOLVED** |
| M10 | IDEA-hook | **checkpoint AI fallback 行为不明确** - What triggers fallback? Network error? 4xx? Format error? No clear thresholds. | **UNRESOLVED** |
| M11 | IDEA-meta | **checkpoint.sh metadata 文件不存在时静默失败** - `_meta_update_checkpoint()` has no else branch. Silent no-op if file missing. | **UNRESOLVED** |
| M12 | IDEA-meta | **worktree 元数据与 git 状态可能脱节** - Metadata only updated by skills. Direct git commands bypass metadata. doctor skill may report incorrect state. | **UNRESOLVED** |
| M13 | IDEA-meta | **start-task.sh 冗余检查** - Lines 62-65 worktree existence check duplicates Lines 33-37. | **LOW PRIORITY** |
| M14 | IDEA-meta | **prepare-push.sh slug 重复计算** - `_ai_assessment()` 内重新计算 slug 而非使用已定义的 WORKTREE_SLUG。 | **LOW PRIORITY** |

### LOW Severity Issues

| ID | Source | Issue | Status |
|----|--------|-------|--------|
| L1 | IDEA-script | **checkpoint.sh 语法检查运行在所有已提交文件** - 100 shell scripts = 100 bash -n checks. Minor performance. | **ACCEPTABLE** |
| L2 | IDEA-script | **prepare-push.sh PRE_REBASE_REF 死代码** - Captured before rebase, never used. | **LOW** |
| L3 | IDEA-script | **resume-task.sh unpushed branch 方向逻辑** - `git log origin/main..origin/$branch` fails if origin/$branch doesn't exist yet. | **LOW** |
| L4 | IDEA-script | **select-worktree.sh 数组索引 off-by-one** - User input "0" selects last element instead of erroring. | **LOW** |
| L5 | IDEA-script | **resume-task.sh broken pipe 处理** - Potential warning from git worktree list --porcelain pipe. | **LOW** |
| L6 | IDEA-ai | **timeout 30s 无区分 log** - User cannot tell timeout vs ccw-not-found vs empty output. | **ACCEPTABLE** |
| L7 | critique | **Detached HEAD guard bypass** - Rule 1 bypassed when current_branch empty. By design (advanced mode). | **BY DESIGN** |

---

## 3. Theme Extraction

| Theme | Strength | Supporting Ideas | Description |
|-------|----------|------------------|-------------|
| **Silent Failures** | 9/10 | B3, H3, H5, M11 | Multiple scripts fail silently when dependencies missing (jq, timeout). Users unaware functionality degraded. |
| **Security Bypass Risk** | 8/10 | B1, B2, H4, M8 | Guard mechanisms have undefined/error behavior that could allow dangerous operations through. |
| **Hook System Undefined Behavior** | 7/10 | B2, H6, M5, M6, M9 | async semantics, Error hooks, skill interaction with PreToolUse all unverified. |
| **Metadata Integrity** | 7/10 | H2, H5, M11, M12 | Metadata can become stale, orphaned, or fail to update without user awareness. |
| **Recovery Path Missing** | 6/10 | H2 | When operations fail mid-way (finish-task), no clear recovery mechanism exists. |

---

## 4. Conflict Resolution

| Conflict | Resolution |
|----------|------------|
| IDEA-script Issue #3 claimed invalid regex `""` existed | **Contradicted by critique**: Verified current code has `^new\ file` only, no empty alternative. Issue does not exist. |
| IDEA-script Issue #2 (timeout missing on macOS) | **Contradicted by critique**: Script already fixed to use `perl -e 'alarm 30'`. Issue mitigated. |
| IDEA-script Issue #6 (finish-task metadata ordering) | **Contradicted by critique**: Code already has correct ordering (metadata deleted after successful removal). Issue mitigated. |
| guard-bash.sh Rule 5 over-blocking | **Resolved as by design**: Intentionally blocks `-fx` (remove ignored files). Clarified in message, acceptable tradeoff. |
| Detached HEAD bypass | **Resolved as by design**: Advanced users in detached HEAD get full access. Not a security hole. |

---

## 5. Integrated Proposals

### Proposal 1: Dependency Guard Wrapper

**Core Concept**: Create a `check-dependencies.sh` that all hook scripts source before execution. Provides consistent error handling for missing dependencies.

**Source Ideas Combined**: B3 (select-worktree jq failure), H3 (checkpoint jq check), H5 (metadata update failure)

**Addressed Challenges**: All jq/script dependencies checked upfront with clear error messages.

**Feasibility**: 8/10 | **Innovation**: 5/10

**Implementation**:
```bash
# check-dependencies.sh
check_dep() {
  if ! command -v "$1" &>/dev/null; then
    echo "ERROR: Required dependency '$1' not found." >&2
    echo "Install: $2" >&2
    return 1
  fi
  return 0
}

# At start of select-worktree.sh, checkpoint.sh, etc.
check_dep jq "brew install jq" || exit 1
```

**Key Benefits**:
- Users get clear error messages instead of silent degradation
- Single source of truth for dependency checking
- Easy to add new dependencies

**Remaining Risks**:
- Need to update all scripts to source this file
- May break existing workflows that don't expect errors

---

### Proposal 2: Error Hook & Recovery Framework

**Core Concept**: Define Error hook in hooks.json and add `--force`/`--recover` flags to finish-task.sh.

**Source Ideas Combined**: B1 (missing guard scripts), H2 (finish-task recovery), H4 (Error hook missing)

**Addressed Challenges**: Guard failures now explicitly deny, finish-task failures have recovery path.

**Feasibility**: 6/10 | **Innovation**: 4/10

**Implementation**:
```bash
# hooks.json - add Error hook
{
  "hooks": {
    "Error": {
      "command": "${CLAUDE_PLUGIN_ROOT}/scripts/error-hook.sh",
      "async": false
    }
  }
}

# error-hook.sh
echo '{"hookSpecificOutput": {"permissionDecision": "deny"}}'
echo "Hook execution failed. If this persists, run: worktree-first doctor"
exit 0

# finish-task.sh --force for broken worktrees
if [[ "$1" == "--force" ]]; then
  git worktree remove --force "$WT_PATH" 2>/dev/null || true
  rm -f "$META_FILE"
  exit 0
fi
```

**Key Benefits**:
- Explicit deny on hook errors (security)
- Recovery path for broken worktrees

**Remaining Risks**:
- hooks.json Error hook behavior unverified with Claude Code
- --force could delete uncommitted work

---

### Proposal 3: Hook Integration Test Suite

**Core Concept**: Create `test/hooks/` with automated tests verifying hook behaviors.

**Source Ideas Combined**: M9 (missing hook tests), B2 (skill vs PreToolUse interaction), H6 (async semantics)

**Addressed Challenges**: No more undefined behavior through verification.

**Feasibility**: 5/10 | **Innovation**: 3/10

**Test Cases Needed**:
1. Verify async=true hook does/doesn't block session
2. Verify skill invocation triggers PreToolUse
3. Verify missing guard script -> Error hook -> deny
4. Verify format script completes before git diff

**Key Benefits**:
- Confidence in hook behavior before production
- Catch regressions early

**Remaining Risks**:
- Hook system may not support testing in isolation
- Async behavior hard to test deterministically

---

## 6. Coverage Analysis

| Angle | Coverage | Key Gaps |
|-------|----------|----------|
| script_correctness | HIGH | slug validation, WT_PATH relative path |
| hook_integration | MEDIUM | async semantics, Error hook, skill interaction |
| ai_fallback_chain | HIGH | All fallback paths verified, jq dependency remains |
| metadata_integrity | MEDIUM | Silent failures, git state脱节 |

---

## 7. Final Verdict

### Summary: Is this plugin safe for production use?

**VERDICT: NO - Not ready for production without fixes**

**Critical blockers requiring resolution**:

1. **B1: Guard script missing = silent security bypass**
   - Without an Error hook definition, missing guard scripts result in undefined behavior
   - Could allow dangerous commands through when guard should be active
   - **Must fix before production**: Add Error hook with explicit deny

2. **B2: Skill invocation bypasses PreToolUse guard**
   - `disable-model-invocation` only prevents model from auto-calling, not user manual skill invocation
   - `/worktree-first:start-task` may bypass `guard-bash.sh` checks entirely
   - **Must fix before production**: Verify skill triggers PreToolUse, or add guard checks inside skills

3. **B3: jq dependency silent failure on macOS**
   - select-worktree.sh produces empty output with exit 0 on macOS (jq not default)
   - Users cannot identify worktrees or see dirty status
   - **Must fix before production**: Add jq availability check with clear error message

### Issues already mitigated (not blockers):

| Issue | Resolution |
|-------|------------|
| checkpoint.sh timeout on macOS | Already fixed with perl-based alarm |
| finish-task.sh metadata ordering | Already fixed (delete after successful removal) |
| Invalid regex `""` pattern | Does not exist in current code |

### Issues by design (not blockers):

| Issue | Rationale |
|-------|-----------|
| guard-bash.sh Rule 5 blocks -fx | Intentionally conservative |
| Detached HEAD bypasses Rule 1 | Advanced user mode |

---

## 8. Recommendations Priority

### Phase 1 (Before Production - BLOCKER fixes)

1. **Add jq dependency check** to all scripts using it (select-worktree.sh, checkpoint.sh, prepare-push.sh)
2. **Add Error hook** to hooks.json for missing guard script handling
3. **Verify skill invocation** triggers PreToolUse hook, or implement guard logic inside skills
4. **Add slug validation** to start-task.sh

### Phase 2 (Soon after - HIGH priority)

5. **Document recovery path** for finish-task.sh worktree removal failure
6. **Add --force flag** to finish-task.sh for broken worktree cleanup
7. **Verify async=true hook semantics** with Claude Code documentation

### Phase 3 (Nice to have - MEDIUM priority)

8. Add hook integration tests
9. Clarify AI fallback trigger conditions
10. Remove redundant start-task.sh checks

---

**Document Status**: Complete synthesis of 4 angle analyses + challenger critique.
**Generated by**: synthesizer role
**Next Action**: Coordinator should route BLOCKER fixes to appropriate executor roles.
