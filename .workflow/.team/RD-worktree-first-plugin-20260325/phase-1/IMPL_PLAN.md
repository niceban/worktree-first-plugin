# Phase 1 IMPL_PLAN — P0 Core Stability Fixes

## Phase Goal
修复 3 项 P0 稳定性问题，其中 P0-0 是本次新增的 guard 体验升级。

---

## Task: IMPL-101 — P0-0: guard 拦截升级为 auto-worktree 引导

**Owner**: executor
**Priority**: P0
**Dependencies**: None
**Status**: pending

### Problem
当前 `guard-main-write.sh` 和 `guard-bash.sh` 只拦截 main 分支危险操作，只显示 deny，不引导到正确状态。用户看到的是"不能这么做"而非"帮你做好"。

### Implementation

#### Step 1: 创建统一的 guard-auto-worktree.sh
新建 `scripts/guard-auto-worktree.sh`，逻辑：

```bash
# 1. 解析 main 分支危险操作
detect_main_write() {
  local cmd="$1"
  # 检测文件写操作（借用 guard-bash.sh Rule 1 的 pattern）
  echo "$cmd" | grep -qE '(\s>>|\s>|\|[[:space:]]*tee\b|...)'
}

# 2. 解析操作类型 → 生成 task slug
generate_slug() {
  local cmd="$1"
  local op_type
  # echo → write, sed → edit, python → script 等
  echo "task-$(date +%Y%m%d-%H%M%S)"
}

# 3. 调用 start-task 创建 worktree
# 4. 切换到新 worktree
# 5. 重放原始命令
```

#### Step 2: 更新 hooks/hooks.json
- PreToolUse: `guard-auto-worktree.sh` 替代原来的两个 guard 脚本
- `async: false`（需要交互确认）

#### Step 3: 更新 skill 文件
- `skills/start-task/` 暴露 `guard-auto-worktree` 内部调用接口

### Success Criteria
用户在 main 上执行 `echo "x" > file.txt`，自动创建 worktree 并完成操作，全程无需手动干预。

### Files
- Create: `scripts/guard-auto-worktree.sh`
- Modify: `hooks/hooks.json`
- Modify: `skills/start-task/*.md`（添加内部 API 说明）

---

## Task: IMPL-102 — P0-1: resume-task.sh 解析 bug 修复

**Owner**: executor
**Priority**: P0
**Dependencies**: None
**Status**: pending

### Problem (Line 11)
```bash
git worktree list --porcelain | while read -r line; do
```
`read` 遇到空白行返回非零退出码，在 `set -euo pipefail` 下导致循环提前终止，只解析第一个 worktree。

### Root Cause
`git worktree list --porcelain` 输出格式：
```
path /Users/c/repo/.worktrees/task-1
branch refs/heads/task/feature-1
HEAD abc1234

path /Users/c/repo/.worktrees/task-2
branch refs/heads/task/feature-2
HEAD def5678
```
空白行是记录分隔符，`read` 遇到空行返回 1（无数据），`set -e` 触发脚本退出。

### Fix
```bash
# 方案：用 awk 代替 while read — awk 自然处理空白行
git worktree list --porcelain | awk '
  $1 == "path" { path = $2 }
  $1 == "branch" { branch = $2 }
  $1 == "HEAD" { head = $2 }
  $0 ~ /^$/ && path != "" {
    # 输出一个完整的 worktree 记录
    print "PATH:" path
    print "BRANCH:" branch
    print "HEAD:" head
    print "---"
    path = ""; branch = ""; head = ""
  }
'
```
参照 `doctor.sh` 已有成功实践（L15-37 的 awk 模式）。

### Success Criteria
创建 3 个 worktree，执行 resume-task.sh，3 个的 slug/branch/HASH 均正确输出。

### Files
- Modify: `scripts/resume-task.sh`（L11-35，换 awk）

---

## Task: IMPL-103 — P0-2: doctor.sh staleness 改用 last_active_at

**Owner**: executor
**Priority**: P0
**Dependencies**: None
**Status**: pending

### Problem (Lines 45-53)
```bash
last_ts=$(git log -1 --format="%ct" "$head" 2>/dev/null || echo "0")
```
用 commit 时间判断 staleness，但 metadata 的 `last_active_at` 更准确：
- commit 10 天前但 metadata 更新过 → 实际是活跃的
- 只有 commit 旧且 metadata 也旧 → staleness

### Fix
```bash
# 读取 metadata 的 last_active_at 而非 git commit 时间
# 在 awk 输出 block 中，收到 PATH: 时加载 metadata
slug=$(basename "$path")
meta_file="${WT_DIR}/${slug}.json"
if [[ -f "$meta_file" ]]; then
  last_active=$(jq -r '.last_active_at // empty' "$meta_file" 2>/dev/null)
  if [[ -n "$last_active" ]]; then
    # 把 ISO 时间转为 unix timestamp
    last_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_active" +%s 2>/dev/null || echo "0")
  fi
fi
# age 计算逻辑不变
```

### Success Criteria
创建一个 worktree（有 metadata），commit 10 天前但 last_active_at 昨天，运行 doctor.sh 不报 staleness。

### Files
- Modify: `scripts/doctor.sh`（L38-59，metadata 读取逻辑）

---

## Wave Assignment

| Wave | Tasks | 依赖 |
|------|-------|------|
| Wave 1 | IMPL-102, IMPL-103 | None（并行） |
| Wave 2 | IMPL-101 | None（独立） |

**注**: 3 个 task 均无依赖，可全并行执行。但 executor 一次处理一个，PLAN → EXEC 串行。
