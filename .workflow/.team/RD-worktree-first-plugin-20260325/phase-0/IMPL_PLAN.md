# Phase 0 IMPL_PLAN — Critical Bug Fixes (D1-D7)

## Phase Goal
修复 Guard 架构的核心设计缺陷，让 worktree-first 插件在真实多 worktree 环境下正常工作。

---

## Root Cause Analysis

### D1 + D2: `cd "$PROJECT_DIR"` 导致永远检查主仓库

```bash
# 错误：永远回到主仓库判断分支
cd "$PROJECT_DIR"
current_branch=$(git symbolic-ref --short HEAD)
```

无论 Bash 命令用 `--cd worktree` 跳到哪里，guard 都回到主仓库的 main branch 判断。正确做法：**不 cd，在 PWD 直接查 git context**。

### 正确模型：检查 PWD 是否在主仓库根目录

```
判断逻辑：
  1. 不 cd，直接在 PWD 执行 git rev-parse --show-toplevel
  2. 如果输出 == PWD 自身 → 在主 worktree（仓库根目录）
  3. 如果 git root 的父目录 == PWD → 在 worktree 里
  4. 如果在 worktree 里 → 检查该 worktree 的 branch 是否为危险 branch
```

### D3: auto-create 还是 deny，不是自动化

Guard hook 只能返回 deny/allow，无法执行 cd。要实现真正自动化，必须：
- PreToolUse 返回 deny + **告知 Claude 下一步操作**（通过 hookSpecificOutput 的 suggestion）
- 或者 Claude Code 的 hook 机制支持"重放"——但目前不支持

**实际可行的方案**：
1. guard 检测到 main worktree 危险操作
2. 返回 deny + 在 reason 中提供切换命令
3. Claude Code 显示 suggestion，用户确认后自动执行

这意味着 **auto-create 还是要 deny**，但 reason 会包含 `cd ../wt/<slug> && <原始命令>` 的 suggestion。

---

## Task: IMPL-001 — 重建 Guard 核心架构

**Owner**: executor
**Priority**: Critical
**Status**: pending

### Fix D1: 移除所有 guard 脚本中的 `cd "$PROJECT_DIR"`

对每个 guard 脚本：
- 删除 `cd "$PROJECT_DIR"` 和相关的 PROJECT_DIR 判断
- 改用 `git -C "$PWD" rev-parse --show-toplevel` 在当前目录查 git root
- **永远不 cd 离开 PWD**

```bash
# 在 PWD 直接查，不改变目录
GIT_ROOT=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "")
[[ -z "$GIT_ROOT" ]] && exit 0  # 不在 git 仓库

# PWD 是否等于 git root → 主 worktree
if [[ "$(realpath "$PWD")" == "$(realpath "$GIT_ROOT")" ]]; then
  IS_MAIN_WORKTREE=true
else
  IS_MAIN_WORKTREE=false
fi
```

### Fix D2: 用 PWD 路径判断而非 branch 判断

```bash
# 新的判断逻辑（替代 branch == "main"）
if [[ "$IS_MAIN_WORKTREE" == "true" ]]; then
  # 在主 worktree，只有文件写/危险命令才 block
  if is_dangerous; then
    DENY with suggestion
  fi
else
  # 在 worktree 里 → 完全放行
  # worktree 是隔离环境，任何操作都是安全的
  exit 0
fi
```

**关键洞见**：worktree 本身就是隔离环境。在 worktree 里执行危险命令只影响该 worktree，不会污染 main。所以 worktree 内应该**完全放行**。

### Fix D4: 用 `git worktree list` 精确判断是否在 worktree 里

```bash
is_worktree_dir() {
  local pwd="$1"
  # git worktree list 的输出包含每个 worktree 的路径
  git worktree list --porcelain | awk '$1 == "path" { print $2 }' | \
    while IFS= read -r wt_path; do
      [[ "$(realpath "$pwd")" == "$(realpath "$wt_path")" ]] && return 0
    done
  return 1
}
```

### Fix D5: auto-create 幂等性检查

```bash
auto_create_worktree() {
  local slug="$1"
  local wt_path="../wt/${slug}"

  # 幂等性检查
  if [[ -d "$wt_path" ]]; then
    echo "Worktree already exists at $wt_path" >&2
    return 1
  fi

  # 创建 worktree...
}
```

### Fix D6: 添加 rollback 机制

```bash
auto_create_worktree() {
  local slug="$1"
  local created=false

  # Step 1: 创建 worktree
  if ! git worktree add -b "task/$slug" "../wt/$slug" origin/main; then
    return 1
  fi
  created=true

  # Step 2: metadata（失败就 cleanup worktree）
  if ! create_metadata "$slug"; then
    [[ "$created" == "true" ]] && git worktree remove "../wt/$slug"
    return 1
  fi

  return 0
}
```

### Fix D7: worktree 路径用 `git worktree add --list` 动态计算

不要硬编码 `../wt/<slug>`，应该：

```bash
# 动态获取主仓库所在目录的父目录
REPO_PARENT=$(dirname "$(git -C "$PWD" rev-parse --show-toplevel)")
WT_BASE="${REPO_PARENT}/wt"
git worktree add -b "task/$slug" "${WT_BASE}/${slug}" origin/main
```

---

## Task: IMPL-002 — 重写 guard-auto-worktree.sh

**Owner**: executor
**Priority**: Critical
**Status**: pending

### 新架构逻辑

```
PreToolUse(guard-auto-worktree.sh):
  1. 读 tool_name + command
  2. 在 PWD（不 cd）查 git root
  3. 判断是否在 main worktree（PWD == git root）
  4. 如果不在 worktree 里（main worktree）：
     - 检测危险操作
     - auto-create worktree
     - 返回 deny + suggestion（含切换命令）
  5. 如果在 worktree 里：exit 0（放行）
```

### suggestion 格式（Claude Code 支持）

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "不能在 main worktree 执行危险操作",
    "suggestions": [
      {
        "description": "创建 worktree 并继续执行",
        "action": "bash",
        "command": "git worktree add -b task/edit-20260325 ../wt/edit-20260325 origin/main && cd ../wt/edit-20260325 && echo 'x' > file.txt"
      }
    ]
  }
}
```

### 合并 guard-bash.sh 和 guard-auto-worktree.sh

将所有 7 条危险规则统一到 guard-auto-worktree.sh，对 main worktree 生效。worktree 内所有操作放行。

---

## Task: IMPL-003 — 更新 hooks.json

**Owner**: executor
**Priority**: Critical
**Status**: pending

- PreToolUse Edit|Write|MultiEdit → guard-auto-worktree.sh（替换 guard-main-write.sh）
- PreToolUse Bash → guard-auto-worktree.sh（替换 guard-bash.sh）
- 删除 guard-main-write.sh 和 guard-bash.sh（合并后不再需要）
- guard-auto-worktree.sh timeout 改为 15（worktree 创建可能稍慢）

---

## Task: IMPL-004 — guard-bash.test.sh 扩展测试

**Owner**: executor
**Priority**: High
**Status**: pending

新增测试场景：
1. main worktree（PWD == repo root）执行危险命令 → deny
2. task worktree（PWD != repo root）执行危险命令 → allow
3. main worktree 执行 `cd worktree && echo x` → allow（--cd 跳到 worktree）
4. auto-create 幂等性：重复 slug → 失败并提示已存在
5. rollback：metadata 创建失败 → worktree 被删除

---

## Wave Assignment

| Wave | Tasks | 说明 |
|------|-------|------|
| Wave 1 | IMPL-001（核心架构重建） | D1+D2+D4+D5+D6+D7 全在里面 |
| Wave 1 | IMPL-003（hooks.json 更新） | 依赖 IMPL-001 |
| Wave 2 | IMPL-002（guard-auto-worktree.sh 完整实现） | 依赖 IMPL-001 的核心函数 |
| Wave 2 | IMPL-004（测试扩展） | 依赖 IMPL-001 + IMPL-002 |
