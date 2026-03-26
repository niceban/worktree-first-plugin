# Hook Integration Ideas - BRS-final-verify-20260324

## Topic
真的可用了么？对我这个插件做最严格的逐行审查

## Angles
- script_correctness
- hook_integration
- ai_fallback_chain
- metadata_integrity

## Mode
Initial Generation

---

## Ideas

### Idea 1: SessionStart async 语义验证

**Title**: SessionStart async=true 语义不明确

**Description**:
`select-worktree.sh` 在 SessionStart hook 中配置为 `async: true`，期望是非阻塞执行。但该脚本内部使用 `read -r user_input` 做交互式选择。如果 async=true 真的表示"不等待结果"，用户将无法完成交互式输入。需要确认 Claude Code hook 系统的 async 语义：是"后台执行"还是"跳过等待用户输入"。

**Key Assumption**:
Claude Code hook 系统对 async=true 的实现是：立即返回，后台运行，不阻塞 session。

**Potential Impact**:
如果语义理解错误，SessionStart 时 select-worktree.sh 会被跳过或立即返回，导致用户无法选择 worktree，session 会在错误的上下文中启动。

**Implementation Hint**:
需要添加测试 case：在有 worktree 存在时启动 session，验证 async=true 时 select-worktree.sh 的输出是否被注入到 session context，以及交互式 read 是否能正常工作。

---

### Idea 2: guard-* 脚本缺失时的错误行为

**Title**: 引用不存在的 hook 脚本会导致静默失败

**Description**:
hooks/hooks.json 中引用了 `${CLAUDE_PLUGIN_ROOT}/scripts/guard-bash.sh` 等路径。如果 `CLAUDE_PLUGIN_ROOT` 环境变量未设置，或脚本文件被误删，hook 执行会失败。需要明确：当 hook 脚本不存在时，系统是报错、跳过、还是以某种默认行为处理？

**Key Assumption**:
当前实现假设所有引用的脚本都存在且可执行。

**Potential Impact**:
如果脚本缺失导致静默失败，则 guard 功能被绕过，存在安全隐患（用户可在 main 分支执行危险操作）。

**Implementation Hint**:
添加防错设计：在 hook 系统层面验证脚本存在性，或在 guard 脚本开头添加自检逻辑，不存在时默认 deny 而非 allow。

---

### Idea 3: disable-model-invocation 与 PreToolUse 的交互盲区

**Title**: disable-model-invocation 无法阻止用户主动调用 skill

**Description**:
`start-task`、`release-tag`、`finish-task` 设置了 `disable-model-invocation: true`，防止模型自动调用。但用户可以直接输入 `/worktree-first:start-task` 触发 skill，此时 PreToolUse 钩子会生效吗？skill 的执行是否经过 PreToolUse？

**Key Assumption**:
skill 触发时，PreToolUse 钩子也会被触发。

**Potential Impact**:
如果 skill 触发不经过 PreToolUse，则用户可以通过直接调用 skill 来绕过 guard-bash.sh 和 guard-main-write.sh 的检查，在 main 分支上执行危险操作。

**Implementation Hint**:
验证 skill 调用链路：用户输入 `/worktree-first:start-task` → 是否经过 PreToolUse hook？如果不经过，需要在 skill 实现内部添加 guard 检查逻辑。

---

### Idea 4: guard-bash.sh 规则覆盖不完整

**Title**: guard-bash.sh 的 git 规则无法覆盖所有危险变体

**Description**:
guard-bash.sh 阻止 `git reset --hard` 但允许 `git reset --hard HEAD~1`（带路径）；阻止 `git push --force` 但未阻止 `git push -f`（短参数）。正则匹配可能有遗漏。

**Key Assumption**:
当前正则 `git[[:space:]]+reset[[:space:]]+--hard` 能覆盖所有危险变体。

**Potential Impact**:
高级用户可能通过参数变体绕过 guard，在 main 分支执行危险重置操作。

**Implementation Hint**:
使用更严格的参数解析而非正则：提取 git 子命令后分别验证，而不是整体匹配。

---

### Idea 5: post-edit-format.sh 的 sync 问题

**Title**: PostToolUse async=true 与格式化冲突

**Description**:
`post-edit-format.sh` 配置为 `async: true`（PostToolUse, Edit|Write|MultiEdit）。该脚本会修改文件（运行 `prettier --write`、`gofmt -w` 等）。如果 async=true 意味着后台执行且不等待，格式化后的文件可能还没有写回磁盘就进入了后续操作。

**Key Assumption**:
PostToolUse 异步执行时，文件系统状态已稳定。

**Potential Impact**:
可能遇到竞态条件：格式化未完成时 git diff 已执行，导致检测到错误的差异。

**Implementation Hint**:
将 async=true 改为 async=false（同步执行），确保格式化完成后再继续。或在脚本内部使用 flock 确保序列化执行。

---

### Idea 6: task-completed-check.sh 超时设置过短

**Title**: TaskCompleted hook timeout=15s 可能不足

**Description**:
`task-completed-check.sh` 执行 git fetch、多次 git diff 检查，可能还有网络延迟。15 秒超时在网络慢或 git 仓库大时可能不够。

**Key Assumption**:
15 秒足够完成所有检查。

**Potential Impact**:
超时导致 hook 被强制终止，TaskCompleted 事件被标记为失败，用户无法完成任务。

**Implementation Hint**:
增加超时到 30s，或在脚本内部对 fetch 添加超时控制（`git fetch --depth=1 origin main` 限制为 shallow fetch）。

---

### Idea 7: hooks.json 缺少 Error/Exception hook

**Title**: 未处理 hook 执行错误的情况

**Description**:
当前 hooks.json 只定义了正常流程的 hook（SessionStart, PreToolUse, PostToolUse, TaskCompleted），没有 Error/Exception hook。当 guard 脚本返回非零退出码或执行超时时，系统如何响应？当前设计假设所有 hook 都成功（exit 0）或明确 deny（exit 0 + JSON），但未处理异常退出。

**Key Assumption**:
hook 执行不会出错，或错误时按 allow 处理。

**Potential Impact**:
hook 脚本 bug 导致非零退出时，可能被误解为 allow，绕过安全检查。

**Implementation Hint**:
定义 Error hook 策略：hook 错误时 deny 而非 allow，或添加 hook 执行结果监控。

---

### Idea 8: select-worktree.sh 的 skill 与 hook 功能重叠

**Title**: select-worktree skill 和 SessionStart hook 重复

**Description**:
`/worktree-first:select-worktree` skill 和 `SessionStart` 中的 `select-worktree.sh`（async=true）功能重叠。skill 需要用户主动调用，hook 在每次 session 启动时自动执行。两者同时存在可能导致重复输出或状态不一致。

**Key Assumption**:
hook 和 skill 可以独立工作，互不干扰。

**Potential Impact**:
用户每次启动 session 都会看到 worktree 列表，即使他已经知道要使用哪个。hook 的自动输出可能干扰用户正在进行的任务。

**Implementation Hint**:
考虑移除 SessionStart 中的 select-worktree.sh，仅通过 skill 主动调用。或让 hook 检测是否已有上下文信息，跳过重复输出。

---

### Idea 9: exit 0 + JSON 语义不一致风险

**Title**: guard 脚本混用两种 deny 格式

**Description**:
`guard-bash.sh` 和 `guard-main-write.sh` 都使用 `exit 0 + JSON` 表示 deny。但 JSON 格式略有不同：`guard-bash.sh` 使用 `hookSpecificOutput.permissionDecision: "deny"`，而 `guard-main-write.sh` 同样使用该结构。如果未来添加的 hook 脚本使用不同格式（如直接 `exit 1` 表示 deny），会产生混乱。

**Key Assumption**:
所有 guard 脚本遵循一致的 exit 0 + JSON deny 约定。

**Potential Impact**:
hook 系统可能解析不了非标准格式，导致 deny 被误解为 allow。

**Implementation Hint**:
在 hooks/hooks.json 文档或 guard 脚本注释中明确规范：所有 guard 脚本必须使用 `exit 0 + JSON { hookSpecificOutput: { permissionDecision: "deny", ... } }` 格式。

---

### Idea 10: 缺少 hook 测试覆盖

**Title**: 没有针对 hook 集成的自动化测试

**Description**:
当前代码库有单元测试和集成测试，但没有针对 hook 集成的测试。无法验证：hooks.json 配置正确被加载、guard 脚本在各种场景下正确 deny/allow、async=true/async=false 的实际行为是否符合预期。

**Key Assumption**:
Hook 系统本身经过测试，或假设它按设计工作。

**Potential Impact**:
Hook 系统的问题不会被发现，直到在真实 session 中触发，此时可能已造成不可逆影响（如 main 分支被错误修改）。

**Implementation Hint**:
添加 hook 集成测试：模拟 PreToolUse 事件，验证 guard 脚本的输出被正确解析和执行。

---

### Idea 11: checkpoint skill 的 AI advisor fallback 行为不明确

**Title**: AI Fallback Chain 在 checkpoint skill 中未被充分定义

**Description**:
`checkpoint` skill 包含 "AI Advisor (P2)" 步骤，描述为"Call LLM to analyze staged diff and recommend... Falls back to rule-based suggestion if LLM unavailable"。但未明确定义：什么算"LLM unavailable"？网络错误？模型拒绝？LLM 返回格式错误？fallback 到规则建议的阈值是什么？

**Key Assumption**:
LLM 不可用时自动 fallback 到规则建议，不会中断用户流程。

**Potential Impact**:
如果 fallback 逻辑不完善，用户可能在关键 checkpoint 时刻遇到阻塞性错误，无法保存进度。

**Implementation Hint**:
明确定义 fallback 触发条件（超时？4xx/5xx 错误？格式错误？）和 fallback 后的用户体验（静默使用规则建议 vs 提示用户）。

---

### Idea 12: worktree 元数据与 git 状态的潜在不一致

**Title**: metadata_integrity 风险：worktree JSON 元数据可能与实际状态脱节

**Description**:
`.worktree-first/worktrees/<slug>.json` 元数据文件记录了 worktree 的 dirty 状态、checkpoints 数量、最后活跃时间等信息。但这些信息是由各个 skill（start-task, checkpoint, finish-task）在适当时机更新的。如果用户在 session 外部直接使用 git 命令操作（例如直接 `git commit` 而非通过 skill），元数据不会更新，导致 `doctor` skill 报告的状态不准确。

**Key Assumption**:
用户总是通过 skill 来操作 git，元数据与实际状态保持同步。

**Potential Impact**:
doctor skill 给出错误的健康报告，用户基于错误信息做决策（如认为一个 dirty 的 worktree 是 clean 的）。

**Implementation Hint**:
在 doctor skill 中增加实时 git 状态检查，不完全依赖元数据；或添加元数据验证步骤，在读取后与 git 实际状态交叉验证。

---

## Summary

本次 hook 集成验证发现了 12 个潜在问题，按角度分布：

**script_correctness** (Ideas 4, 6, 9, 10):
- guard-bash.sh 正则覆盖不完整
- task-completed-check.sh 超时过短
- guard 脚本 deny 格式不一致
- 缺少 hook 集成测试

**hook_integration** (Ideas 1, 2, 3, 5, 7, 8):
- async=true 语义不明确
- 缺失脚本导致静默失败
- disable-model-invocation 无法阻止用户调用 skill
- PostToolUse async 竞态
- 缺少 Error hook
- skill 与 hook 功能重叠

**ai_fallback_chain** (Idea 11):
- checkpoint skill 的 AI advisor fallback 行为不明确

**metadata_integrity** (Idea 12):
- worktree 元数据可能与 git 实际状态脱节

**优先验证建议**:
1. async=true 语义（影响核心流程）
2. disable-model-invocation 与 PreToolUse 的交互（影响安全机制）
3. 缺失脚本的处理（影响防御完整性）
