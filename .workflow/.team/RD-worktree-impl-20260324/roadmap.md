# Worktree-First Plugin: P0-P2 Implementation Roadmap

## Session
- **ID**: RD-worktree-impl-20260324
- **Project**: worktree-first-plugin
- **Objective**: 完整实现 P0-P2 所有需求并测试验证

---

## Phase Definitions

### Phase P0: Foundation Stabilization

**目标**: 修复合临界 bugs，确保插件在所有关键路径上不崩溃。

| Task ID | 内容 | Success Criteria |
|---------|------|----------------|
| P0-01 | start-task 幂等化 | 重复调用同一个 slug 不失败，输出"已存在"而非 error | **COMPLETED** |
| P0-02 | 危险命令 blocklist 补全 | `git reset --hard`（无路径）被拦；所有 Rule 覆盖完整 |
| P0-03 | prepare-push rebase rollback | rebase 失败时自动 offer rollback，用户知道怎么恢复 |
| P0-04 | 结构化元数据存储 | `.worktree-first/worktrees/<slug>.json` 正确创建和更新 |

**验证标准**: 所有 guard-bash.sh regex 通过 18 个测试 case；元数据文件在每个操作后正确更新。

---

### Phase P1: Workflow Enhancement

**目标**: UX 改进，降低用户认知负担。

| Task ID | 内容 | Success Criteria |
|---------|------|----------------|
| P1-01 | select-worktree 交互选择器 | 用户开新 session 时能看到所有 worktree 列表并选择 |
| P1-02 | checkpoint 消息辅助 | commit 前基于 diff 生成建议消息，用户可接受或修改 |
| P1-03 | prepare-push 进度提示 | 每个 step 有明确的状态输出，用户知道现在在跑哪一步 |

**验证标准**: select-worktree 在空项目和有多 worktree 项目都能正常展示；checkpoint 消息生成正确。

---

### Phase P2: AI-Native Enhancement

**目标**: 引入 AI 判断层，但不是 blocker。

| Task ID | 内容 | Success Criteria |
|---------|------|----------------|
| P2-01 | AI Checkpoint Advisor | checkpoint 前调 LLM，分析 diff 是否值得 commit |
| P2-02 | AI Push Readiness Assessor | prepare-push 前给 1-5 星 PR 准备度评分 + 理由 |

**验证标准**: AI 调用成功返回结果；结果可读且对用户有参考价值。

---

## Dependencies

```
P0-01 → P0-04 (元数据是后续基础)
P0-02 → P1-01 (危险命令完整才能安全地做选择器)
P0-04 → P1-01 (选择器需要读 meta.json 展示状态)
P0-04 → P1-02 (checkpoint 需要更新 meta.json)
P1-01 → P2-01 (AI advisor 依赖基础 state)
```

---

## Success Criteria (Overall)

1. 所有 9 个 Task ID 全部完成
2. guard-bash.sh 18/18 测试通过
3. `claude plugin validate` 通过
4. 真实 Claude Code session 中 hooks 正常工作
5. 无新增 regression（现有功能不被破坏）
