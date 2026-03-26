# Roadmap: worktree-first-plugin 全自动托管

## 目标
让 worktree-first-plugin 成为开发者**全自动托管（无需关注）**的 Git 插件套件。从 start-task 到 PR merge 到 branch 清理，全部自动化，开发者只需要提交代码。

---

## Phase 1: P0 核心稳定性修复

### P0-0: guard 拦截升级为 auto-worktree 引导（核心体验升级）
**问题**: 当前 guard 机制只在 main 分支拦截危险操作（Write/Bash），只告诉用户"不能这么做"，不引导到正确状态。这是**半成品体验**。
**设计升级**: 拦截 → 自动创建 worktree → 重放命令
**修复**:
- `guard-main-write.sh` 和 `guard-bash.sh` 合并重构为统一的 `guard-auto-worktree.sh`
- 检测到 main 分支危险操作时：
  1. 自动解析操作类型（文件写？命令执行？）
  2. 自动生成 task slug（基于操作类型 + 时间戳）
  3. 自动调用 `start-task.sh` 创建 worktree
  4. 自动切换到新 worktree 分支
  5. 重放用户原始命令
- 对话式确认：操作前询问 "检测到 main 分支写操作，已为你创建 worktree `{slug}`，是否继续？(y/n)"
- **完全替换原有 guard 逻辑**：不再单纯拦截，而是引导到正确状态
**Success Criteria**: 用户在 main 上执行 `echo "x" > file.txt`，自动创建 worktree 并完成操作，全程无需手动干预。

### P0-1: resume-task.sh 解析 bug 修复
**问题**: `git worktree list --porcelain` 输出以空白行分隔，`while read -r line` 遇到空白行会提前终止，导致 worktree 路径解析不完整。
**修复**: 改用 `while IFS= read -r line` 配合空白行判断，正确处理多 worktree 场景。
**Success Criteria**: 任意数量 worktree（≥2）都能正确解析出所有 slug、路径、分支。

### P0-2: doctor.sh staleness 判断修复
**问题**: staleness 用 `git log -1 --format="%ct"`（commit 时间）判断，10 天前的 commit = staleness，但 metadata 里有 `last_active_at` 更准确。
**修复**: 改用 `.worktree-first/worktrees/<slug>.json` 的 `last_active_at` 而非 commit 时间。
**Success Criteria**: doctor.sh 能正确区分"活跃 task"和"长期无操作 task"。

---

## Phase 2: P1 metadata 安全 + guard-bash 扩展

### P1-1: metadata 备份机制
**问题**: metadata 文件（`.worktree-first/worktrees/*.json`）写入前没有备份，异常断电/进程崩溃可能损坏。
**修复**: 写入前自动 `cp <file> <file>.bak`，保留最近 N 份（可配置，默认 3）。
**Success Criteria**: metadata 更新前有备份，更新失败可从备份恢复。

### P1-2: orphaned metadata 清理（doctor --fix 模式）
**问题**: worktree 已被手动删除，但 metadata 文件残留，造成 ghost task。
**修复**: `doctor.sh --fix` 扫描 metadata 中的 worktree 路径，对比 `git worktree list`，删除 orphaned metadata。
**Success Criteria**: `doctor.sh --fix` 能清理 ghost metadata，不影响真实 task。

### P1-3: guard-bash 新增 git worktree remove 拦截
**问题**: `git worktree remove <path>` 直接删除 worktree，不走 finish-task 流程，导致 metadata 残留。
**修复**: 在 guard-bash.sh 新增规则，拦截非 `--force` 的 `git worktree remove`（允许 force）。
**Success Criteria**: `git worktree remove` 被拦截，提示用 `/worktree-first:finish-task` 代替。

---

## Phase 3: P1 PR 自动化集成

### P1-4: prepare-pr + gh pr create 集成
**问题**: prepare-push 完成后，用户还需手动在 GitHub 网页上创建 PR。
**修复**:
- `prepare-pr.sh` skill：在 `prepare-push` 成功后，提示用户确认 PR 标题和内容
- 用户确认后，自动调用 `gh pr create --title <title> --body <body> --base main`
- 自动填充 changed files summary + checkpoint history 作为 PR description
**Success Criteria**: 用户运行 `/worktree-first:prepare-pr`，确认标题内容后 PR 自动创建。

---

## Phase 4: P2 自动化增强

### P2-1: SessionStop hook — session 结束时自动 checkpoint
**问题**: 用户关闭 session 时，工作状态（dirty flag、checkpoint 记录）没有自动保存。
**修复**: 在 `hooks/hooks.json` 新增 `SessionStop` hook，调用 `checkpoint.sh` 保存状态（不调 AI advisor）。
**Success Criteria**: session 结束时，metadata 的 `last_active_at` 更新，`dirty` 状态保留。

### P2-2: 定时 rebase 提醒机制
**问题**: 长期待办 task 落后 main 太多，没有提醒。
**修复**: `doctor.sh` 在检测到 task branch 落后 main 超过 5 个 commit 时，输出警告提示。
**Success Criteria**: `doctor.sh` 运行时，对落后 5+ commit 的 task 输出 "⚠️ 落后 main X commits，建议 rebase"。

### P2-3: metadata integrity 检查
**问题**: metadata JSON 可能因写入中断而损坏，导致 `jq` 解析失败。
**修复**: 定期（如 doctor.sh 运行前）用 `jq . <file>` 验证所有 JSON 完整性，损坏的文件备份并重建。
**Success Criteria**: doctor.sh 能检测并修复损坏的 metadata 文件。

### P2-4: prepare-push 自动 squash（用户只需确认最终 commit message）
**问题**: 当前 prepare-push 要求 squash 后用户手动写 commit message，流程繁琐。
**修复**:
- 检测到 >1 commit 时，自动 squash 到一个临时 commit
- 调 AI advisor 生成默认 commit message 填入，用户只需确认/修改
- 确认后完成 rebase + push readiness 评估
**Success Criteria**: prepare-push 能自动完成 squash + 生成 commit message 草稿，用户只需确认。

---

## Success Criteria 总览

| Phase | Task | 验证方式 |
|-------|------|---------|
| Phase 1 | P0-0 guard → auto-worktree | main 上执行写操作，自动创建 worktree 并完成操作 |
| Phase 1 | P0-1 resume-task 解析 | 创建 3 个 worktree，resume 每个，确认都能解析 |
| Phase 1 | P0-2 doctor staleness | 有 metadata 但 commit 旧的 task，确认不报 staleness |
| Phase 2 | P1-1 metadata 备份 | 触发 metadata 更新，确认有 .bak 文件 |
| Phase 2 | P1-2 orphaned cleanup | 手动删 worktree，运行 doctor --fix，确认清理 |
| Phase 2 | P1-3 worktree remove 拦截 | 运行 `git worktree remove`，确认被拦截 |
| Phase 3 | P1-4 prepare-pr | 运行 prepare-pr，确认 gh pr create 成功 |
| Phase 4 | P2-1 SessionStop hook | 关闭 session，确认 last_active_at 更新 |
| Phase 4 | P2-2 rebase 提醒 | 创建落后 5+ commit 的 task，运行 doctor，确认警告 |
| Phase 4 | P2-3 integrity check | 手动破坏 JSON，运行 doctor，确认检测并修复 |
| Phase 4 | P2-4 auto-squash | >1 commit 时运行 prepare-push，确认自动 squash + 草稿 |
