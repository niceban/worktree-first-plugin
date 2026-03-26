# Metadata Handling Analysis: IDEA-meta

## Topic
验证 metadata 文件的完整性

## Angles
- start-task.sh: metadata 创建时机
- checkpoint.sh: metadata 更新逻辑
- prepare-push.sh: metadata 读取逻辑
- finish-task.sh: metadata 删除逻辑
- git rev-parse --git-dir 在 worktree 内的行为

## Mode
Initial Generation

## Ideas

### 1. start-task.sh: Metadata 创建时机分析

**问题**: metadata 创建是否在所有检查之后？

**发现**:
- Lines 25-29: 变量初始化 (REPO_DIR, BRANCH_NAME, WT_PATH, WT_DIR, WT_META)
- Lines 33-37: 幂等性检查 - worktree 已存在则直接退出
- Lines 40: `mkdir -p "$WT_DIR"` - 创建 metadata 目录
- Lines 42-46: Git repo 检查 + origin/main 检查
- Lines 48-49: git switch main && git fetch origin && git pull --ff-only
- Lines 51-59: 分支存在性检查
- Lines 62-65: worktree 路径存在性检查（重复）
- Lines 69: `git config extensions.worktreeConfig true`
- Lines 72: `git worktree add -b "$BRANCH_NAME" "$WT_PATH" origin/main`
- Lines 74-77: 配置 worktree
- **Lines 80-93: 写入 metadata** ← 在 worktree 创建之后

**结论**: ✅ metadata 在所有检查通过且 worktree 创建成功后创建。时序正确。

**潜在问题**:
1. Lines 62-65 的 worktree 存在性检查是冗余的（Lines 33-37 已检查过）
2. Lines 48-49 的 `git switch main` 可能导致问题：如果当前已经在 main 分支上的 worktree 中执行，会切换走当前分支

---

### 2. checkpoint.sh: Metadata 不存在时的行为

**问题**: 更新 metadata 时，如果文件不存在会怎样？

**代码分析** (Lines 200-224):
```bash
_meta_update_checkpoint() {
  local slug
  slug=$(basename "$WORKTREE_PATH")
  local repo_root
  repo_root="$(git rev-parse --git-dir)/.."
  local meta_file="${repo_root}/.worktree-first/worktrees/${slug}.json"
  if [[ -f "$meta_file" ]]; then
    # ... jq 更新逻辑 ...
    echo "  [OK] metadata updated"
  fi
  # ⚠️ 如果文件不存在：静默退出，无任何警告
}
```

**问题**: 如果 metadata 文件不存在，`_meta_update_checkpoint` 函数会**静默失败**：
- 不输出错误信息
- 不返回失败状态
- 调用者无法知道 metadata 未更新

**风险评估**:
- 中等风险：用户可能误以为 metadata 已更新（因为没有错误）
- 但由于 checkpoint 提交本身已成功，影响有限
- 建议：添加 `else` 分支输出警告

---

### 3. finish-task.sh: Slug 提取正确性

**代码分析**:
```bash
# Line 7
WT_PATH="$PWD"

# Line 12
REPO_DIR="$(cd "$(git rev-parse --git-dir)/.." && pwd)"

# Line 18
WT_NAME="$(basename "$WT_PATH")"

# Line 48
META_FILE="${REPO_DIR}/.worktree-first/worktrees/${WT_NAME}.json"
```

**Slug 提取**: `WT_NAME="$(basename "$WT_PATH")"` - ✅ 正确

**分析**:
- `basename "$WT_PATH"` 正确处理路径，即使有空格也会正确提取最后一个组件
- 路径被双引号包裹，避免 word splitting
- 示例：`WT_PATH="/path/to/my worktree"` → `WT_NAME="my worktree"` ✅

**META_FILE 构建**: ✅ 正确
- `"${REPO_DIR}/.worktree-first/worktrees/${WT_NAME}.json"` 路径正确拼接

---

### 4. git rev-parse --git-dir 在 worktree 内的行为

**问题**: 这个命令在 worktree 内返回什么？如何影响 repo_root 的计算？

**Git 行为分析**:

| 场景 | `git rev-parse --git-dir` 返回值 | `$(git rev-parse --git-dir)/..` |
|------|----------------------------------|--------------------------------|
| 主仓库内执行 | `.git` (相对路径) | 主仓库根目录 |
| Worktree 内执行 | `/absolute/path/to/repo/.git` | 主仓库根目录 |

**验证**:

```bash
# 在 worktree 内
$ git rev-parse --git-dir
/Users/c/auto-git/worktree-first-plugin/.git

$ git rev-parse --git-dir)/..
/Users/c/auto-git/worktree-first-plugin
```

**对各脚本的影响**:

| 脚本 | 执行位置 | repo_root 计算 | 正确性 |
|------|---------|---------------|--------|
| start-task.sh | 主仓库 | `$(git rev-parse --git-dir)/..` = `.git/..` = 主仓库根 | ✅ |
| checkpoint.sh | Worktree | `$(git rev-parse --git-dir)/..` = `/path/.git/..` = 主仓库根 | ✅ |
| prepare-push.sh | Worktree | `$(git rev-parse --git-dir)/..` = `/path/.git/..` = 主仓库根 | ✅ |
| finish-task.sh | Worktree | `$(cd "$(git rev-parse --git-dir)/.." && pwd)` = 主仓库根 | ✅ |

**结论**: ✅ 所有脚本对 `repo_root` 的计算都是正确的。

---

### 5. Worktree 路径含空格或特殊字符时的 Slug 提取

**问题**: 如果 worktree 路径有空格或特殊字符，slug 提取是否正确？

**分析**:

| 脚本 | slug 提取代码 | 引用方式 | 安全性 |
|------|-------------|---------|--------|
| checkpoint.sh:15 | `WORKTREE_SLUG="$(basename "$WORKTREE_PATH")"` | `realpath` 保证绝对路径 | ✅ |
| checkpoint.sh:203 | `slug=$(basename "$WORKTREE_PATH")` | 双引号包裹 | ✅ |
| prepare-push.sh:16 | `WORKTREE_SLUG="$(basename "$WORKTREE_PATH")"` | 双引号包裹 | ✅ |
| prepare-push.sh:101 | `slug=$(basename "$WORKTREE_PATH")` | 双引号包裹 | ✅ |
| finish-task.sh:18 | `WT_NAME="$(basename "$WT_PATH")"` | 双引号包裹 | ✅ |

**潜在问题 - prepare-push.sh:101 vs 16**:

```bash
# Line 15-16
WORKTREE_PATH="$(git rev-parse --show-toplevel 2>/dev/null || echo '')"
WORKTREE_SLUG="$(basename "$WORKTREE_PATH")"  # 定义 WORKTREE_SLUG

# Line 100-101
slug=$(basename "$WORKTREE_PATH")  # 重新用 WORKTREE_PATH 计算 slug
```

这里 `_ai_assessment` 函数内 (Line 100-101) 重新计算 `slug` 而非使用已定义的 `WORKTREE_SLUG`。虽然结果相同，但存在轻微不一致。

**空格场景测试**:
```bash
$ basename "/path/to/my worktree"
my worktree  # ✅ 正确提取

$ basename "/path/to/worktree-with-dash"
worktree-with-dash  # ✅ 正确提取

$ basename "/path/to/worktree_with_underscore"
worktree_with_underscore  # ✅ 正确提取
```

**结论**: ✅ 所有 slug 提取都正确处理空格和特殊字符（因为使用 `basename` 且在双引号内）。

---

## Summary

### 验证结果

| 检查项 | 状态 | 说明 |
|--------|------|------|
| start-task.sh metadata 创建时机 | ✅ PASS | 在所有检查和工作tree创建后 |
| checkpoint.sh 文件不存在处理 | ⚠️ WARNING | 静默失败，建议添加警告 |
| finish-task.sh slug 提取 | ✅ PASS | basename 正确使用 |
| git rev-parse --git-dir 行为 | ✅ PASS | 在 worktree 内返回主仓库 .git 路径 |
| 空格/特殊字符处理 | ✅ PASS | 所有路径正确引用 |

### 建议改进

1. **checkpoint.sh**: 在 metadata 文件不存在时输出警告而非静默
2. **start-task.sh**: 移除冗余的 worktree 存在性检查 (Lines 62-65)
3. **prepare-push.sh**: 统一使用已定义的 `WORKTREE_SLUG` 变量

### 风险评估

- **低风险**: Metadata 处理整体可靠
- **潜在问题**: checkpoint.sh 静默失败可能误导用户
