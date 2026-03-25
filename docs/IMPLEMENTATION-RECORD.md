# Worktree-First Plugin: 完整实现记录

## 项目结构

```
worktree-first-plugin/
├── .claude-plugin/
│   └── plugin.json          # 插件元数据
├── hooks/
│   └── hooks.json           # PreToolUse/PostToolUse/TaskCompleted hooks
├── scripts/
│   ├── guard-bash.sh        # PreToolUse: 危险命令拦截（7 条规则）
│   ├── guard-main-write.sh  # PreToolUse: Write 工具拦截 main 分支写
│   ├── post-edit-format.sh  # PostToolUse: 格式化钩子
│   ├── task-completed-check.sh
│   ├── repo-status.sh       # SessionStart: 显示 repo 状态
│   ├── select-worktree.sh  # SessionStart: 交互式 worktree 选择
│   ├── start-task.sh        # 创建新 task worktree
│   ├── checkpoint.sh        # 创建 checkpoint + AI advisor
│   ├── prepare-push.sh      # rebase + clean history + AI 评估
│   └── finish-task.sh       # 清理 worktree + branch
├── skills/                  # 5 个 Claude Code skill
│   ├── start-task/
│   ├── checkpoint/
│   ├── prepare-push/
│   ├── finish-task/
│   └── select-worktree/
└── tests/
    └── guard-bash.test.sh   # Python 测试套件（37 case）
```

---

## hooks/hooks.json — 完整配置

```json
{
  "hooks": {
    "SessionStart": [
      { "command": "${CLAUDE_PLUGIN_ROOT}/scripts/repo-status.sh", "async": false },
      { "command": "${CLAUDE_PLUGIN_ROOT}/scripts/select-worktree.sh", "async": false }
    ],
    "PreToolUse": [
      { "matcher": "Edit|Write|MultiEdit", "command": ".../guard-main-write.sh", "timeout": 10 },
      { "matcher": "Bash", "command": ".../guard-bash.sh", "timeout": 10 }
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write|MultiEdit", "command": ".../post-edit-format.sh", "async": true }
    ],
    "TaskCompleted": [
      { "command": ".../task-completed-check.sh", "timeout": 15 }
    ]
  }
}
```

**关键决策**: `select-worktree.sh` 必须 `async: false`（interactive `read` 需要 blocking）

---

## guard-bash.sh — 7 条规则（最终版）

### Rule 1: main 分支文件写拦截
**Pattern**:
```bash
'(\s>>|\s>|\|[[:space:]]*tee\b|\|cat\s*>|sed\s+-i|perl\s+-i|\S\.write\(|truncate|dd\b.*of=|tr\b.*of=)'
```
**Exception**: `[^>]*>(2\s*)?\s*/dev/null`（允许 `>/dev/null` 和 `2> /dev/null`）

### Rule 2: git push to main
**Pattern**: `git[[:space:]]+push[[:space:]]+[^;]*main|...refs/heads/main`

### Rule 3: bare --force（允许 --force-with-lease）
**Pattern**:
```bash
# 长形式 --force（用双引号让 $ 展开）
'git[[:space:]]+push[[:space:]]+[^;]*--force($| )'
# 短形式 -f
'git[[:space:]]+push[[:space:]]+[^;]*'"-f($| )"
```
**关键**: `"--force($| )"` 的双引号让 bash 展开 `$`，产生 ` --force` 或 ` -force` 后跟边界

### Rule 4: git reset --hard 无目标（bare form）
**Pattern**: `'git[[:space:]]+reset[[:space:]]+--hard$'`
**说明**: `git reset --hard HEAD~1` 有明确目标，不拦截（由 Rule 7 管的更细）

### Rule 5: git clean -x/-X（销毁 ignored 文件）
**Pattern**: `'git[[:space:]]+clean[[:space:]]+-[fFxX]([dD]*[xX]+[dD]*)$'`
**根因**: 原始 pattern `([xX]|[dD][xX])$` 只能匹配 ≤2 字符
**修复**: `[dD]*[xX]+[dD]*` 允许任意数量 d/D 围绕 x/X

### Rule 6: 删除 main/master
**Pattern**: `'git[[:space:]]+branch[[:space:]]+-[Dd][[:space:]]+(main|master)'`

### Rule 7: 已合并到 Rule 4（移除冗余规则）
**原因**: `git reset --hard HEAD~1` 有明确目标，应该允许；`git reset --hard` 无目标应该拦截

---

## checkpoint.sh — AI Advisor 实现细节

### AI 调用链
```
1. git diff --cached 获取 staged diff
2. ccw cli --mode write（不是 analysis — analysis 返回文本不是 JSON）
3. perl -e 'alarm shift; exec @ARGV' 30 -- ccw cli（30s 超时，macOS 兼容）
4. jq -r 解析 judgment/reason/suggested_message
5. 通过 temp 文件 + SUGGESTION: 前缀传回建议消息
```

### 返回值语义
- `return 0`: AI 成功返回，judgment/reason 解析成功
- `return 1`: ccw 调用失败或解析失败
- 调用者通过 `$?` 判断走哪个分支

### JSON 解析方式
```bash
# SUGGESTION: 前缀行用于跨函数传递建议消息
[[ -n "$suggested_msg" ]] && echo "SUGGESTION: checkpoint: $suggested_msg"
# 调用者通过 grep 提取
ai_suggestion=$(grep '^SUGGESTION:' "$ai_out_file" | sed 's/^SUGGESTION: //')
```

---

## prepare-push.sh — Step 3 AI 评估

### STAR_RATING 解析
```bash
if [[ "$assessment" =~ STAR_RATING:\ ([0-5])/5 ]]; then
  stars="${BASH_REMATCH[1]}"
  echo "=== AI Push Readiness: $stars/5 stars ==="
fi
```

### macOS timeout 问题
- **错误**: `timeout 30 ccw cli ...`（macOS 没有 timeout）
- **正确**: `perl -e 'alarm shift; exec @ARGV' 30 -- ccw cli ...`
- **注意**: SIGALRM 退出码是 142（不是 Linux timeout 的 124）

### rebase rollback
```bash
PRE_REBASE_REF=$(git rev-parse HEAD)
if ! git rebase origin/main; then
  git rebase --abort
  echo "Rebase failed. Your changes are intact."
  exit 1
fi
```

---

## 测试套件: guard-bash.test.sh

### 框架选择
**Python** 而非 bash:
- 避免了 `set -e` + `grep -q` 的 pipefail 问题
- JSON 序列化通过 `json.dumps()` 解决，无需手动转义
- `subprocess.run()` 可精确控制输出捕获

### 37 case 覆盖

| 规则 | Case 数 | 关键测试 |
|------|---------|---------|
| Rule 1 | 13 | main 分支文件写拦截 + /dev/null 例外 |
| Rule 2 | 4 | git push to main 各种形式 |
| Rule 3 | 3 | --force / -f / --force-with-lease |
| Rule 4 | 3 | reset --hard / --soft / HEAD |
| Rule 5 | 6 | -fdx / -fdX / -fdxd / -fdxx / -fd / -f |
| Rule 6 | 6 | -d/-D main/master vs feature |
| Rule 7 | 2 | bare --hard vs --hard HEAD~1 |

---

## 插件安装（本地手动安装）

### 步骤
1. 创建 cache: `~/.claude/plugins/cache/worktree-first/worktree-first/<version>/`
2. 创建 marketplace: `~/.claude/plugins/marketplaces/worktree-first/.claude-plugin/marketplace.json`
3. 注册 `~/.claude/plugins/installed_plugins.json`
4. 添加到 `~/.claude/settings.json` 的 `enabledPlugins`
5. 创建 marketplace 元数据

### 注意
- git push 后 cache 不会自动同步
- 需要手动 `cp -r` 更新 cache 目录

---

## 回顾：哪些预期和实际不同

| 预期 | 实际 | 影响 |
|------|------|------|
| guard-bash.sh 有 18 个测试用例 | 实际上没有任何测试文件 | 创建了 37 case 测试套件 |
| checkpoint.sh AI advisor 两分支都 return 0 | 失败分支 return 1 | 无问题，逻辑正确 |
| prepare-push.sh 用 `timeout` | macOS 没有 timeout | 改用 perl alarm |
| Rule 5 pattern 匹配 -fdx/-fdX | 原 pattern 只能匹配 ≤2 字符 | 修复为 [dD]*[xX]+[dD]* |
