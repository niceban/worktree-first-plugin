# Challenger 视角：对 worktree-first 插件改法的质疑

## 背景

当前改法方向：新增 `select-worktree.sh` + `start-task` 增强（AI 判断层）+ session/branch 关系维护 + 半成品不 commit + 开工/收工自动化。

---

## 挑战 1：select-worktree.sh 交互设计是否过于复杂？

**核心论点**：当前 `resume-task` 已经在输出结构化的 worktree 列表并通过 SKILL.md 引导交互。新的 `select-worktree.sh` 是否在解决一个不存在的问题？

**尖锐问题**：

1. **"交互式选择"解决的是谁的痛点？**
   - 如果用户在 terminal 工作，他们已经可以看到 `git worktree list` 输出。新的交互层只是在前端加了一层 wrapper。
   - 如果用户在 Claude 对话中工作，SKILL.md 已经提供了自然的语言交互接口。引入独立的 shell 脚本不会让体验更一致，反而引入了两种交互模式。
   - **反驳**：你确定用户需要一个新的 CLI 交互，而不是在现有 SKILL.md 流程中增强？

2. **"简洁"和"功能完整"之间的权衡是否被认真评估过？**
   - 每增加一层交互，就增加一层学习成本和出错可能。
   - `resume-task` 的现有输出已经包含了 branch、path、dirty/clean 状态、unpushed commits。你说的"更简洁方案"具体指什么？去掉某些信息？那这些信息对用户没价值吗？

3. **脚本的可组合性如何保证？**
   - 如果 `select-worktree.sh` 输出了一个 worktree 路径，后续流程能否无缝衔接？还是需要 grep/parse 文本输出？
   - **追问**：你是否考虑过用 `git worktree list --format='%(path)'` 这样的标准化输出，而不是人工解析文本？

---

## 挑战 2：session 和 branch 关系维护是否真的必要？

**核心论点**：Git worktree 本身就是 session 隔离机制。再加一层 session→branch mapping 是在重复造轮子，还是真的在解决某个 Git 无法解决的问题？

**尖锐问题**：

1. **"session"在这里的定义是什么？**
   - 如果指的是 Claude conversation session，那它和 Git branch 是两个完全不同维度的概念。
   - 一个 Claude session 可以在多个 Git branch 之间切换（通过 `git worktree add` 创建新的 worktree）。
   - 一个 Git branch 可能被多个 Claude session 访问（不同时间、不同会话）。
   - **追问**：你维护这个映射关系是为了解决什么具体问题？恢复中断的工作？审计谁在哪个 branch 做了什么？

2. **如果目的是"恢复中断的工作"，现有的 `git worktree list` + `resume-task` 已经够用：**
   - worktree path 就是物理隔离
   - branch name 就是逻辑隔离
   - 最后一次 commit 就是进度标识
   - **反驳**：加一层 session tracking 不会让"恢复工作"变得更容易，反而需要额外的状态存储和同步。

3. **这个映射关系谁来维护一致性？**
   - 如果 Claude session 崩溃了，session→branch 映射谁来清理？
   - 如果用户手动 `git worktree remove`，映射谁来更新？
   - 如果用户用另一个 terminal 直接 `git checkout`，映射会不会 stale？
   - **追问**：你设计的这个映射关系，系统自愈能力在哪里？

---

## 挑战 3：AI 判断层是否会让插件变得太重？

**核心论点**：当前插件是"规则驱动"的——用户显式调用命令，插件执行。引入 AI 判断后，行为变得不可预测，且增加了外部依赖。

**尖锐问题**：

1. **"AI 判断"判断什么？判断错了谁来负责？**
   - 如果 AI 判断"现在应该 checkpoint"，但用户实际在做一个不该 checkpoint 的 mid-state，这个误判怎么撤回？
   - 如果 AI 判断"可以 prepare-push"，但实际上代码还没测完，这个错误怎么追踪？
   - **追问**：AI 的判断依据是什么？规则引擎还是 LLM？前者为什么不直接写规则，后者如何保证一致性？

2. **AI 判断层引入了哪些新依赖？**
   - LLM API 调用的延迟和成本
   - 网络可用性
   - 模型版本变化导致的行为漂移
   - Prompt injection 风险（如果判断逻辑可被用户输入影响）
   - **反驳**：一个本地 Git 插件，一旦引入外部 AI 服务，还能叫"轻量工具"吗？

3. **AI 判断的价值是否大于其成本？**
   - 当前用户主动调用 `/worktree-first:checkpoint` 需要 1 秒思考和输入。
   - AI 判断需要：API 调用（可能 3-10 秒）+ 可能的误判风险 + 调试困难。
   - **问题**：对于一个 git 插件来说，"自动 checkpoint"真的是刚需还是过度设计？

---

## 挑战 4：半成品不 commit 的设计在实际开发中是否可行？

**核心论点**：`checkpoint` 机制要求用户主动 staging + commit。设计"半成品不 commit"意味着需要某种持久化但非 commit 的存储机制（如 stash、WIP branch、或者纯文件）。

**尖锐问题**：

1. **Git 的设计本身就是"commit 即快照"。绕过 commit 意味着你在对抗 Git 的核心设计哲学：**
   - `git stash` 是为临时切换分支设计的，不是为长期半成品存储设计的。
   - WIP branch 是一种 hack，等于用 branch 模拟 stash。
   - **追问**：如果半成品不 commit，它怎么和 `git rebase` / `git merge` 协作？冲突怎么解决？

2. **"半成品不 commit"和"可以被恢复"是两件事：**
   - checkpoint 的价值不只是保存进度，还包括提供一个清晰的回退点。
   - 如果半成品存在文件系统的某个角落，它和 Git 历史的关系是什么？
   - **反驳**：你是在解决"commit 污染历史"的问题，还是在制造一个新的"半成品存在哪"的问题？

3. **现实开发中，"半成品"经常是"不确定要不要的尝试"：**
   - 这种场景 stash 比 commit 更适合，但 stash 本身就不算"commit"。
   - 如果你的设计让用户必须在"commit 污染历史"和"丢失工作"之间二选一，这不是一个好的设计。
   - **追问**：你说的"半成品不 commit"具体指哪种场景？intent-based commit 还是真的 WIP？

---

## 挑战 5：开工/收工自动化是否真的必要，还是只是改善而非必需？

**核心论点**：`start-task` 和 `finish-task` 已经是单命令操作。自动化（如自动 fetch main、自动清理 merged branch）节省的时间是否值得投入的开发成本？

**尖锐问题**：

1. **`start-task` 已经是一行命令。你自动化的是哪一步？**
   - 如果是"自动 fetch main"——这在脚本里已经是 `git fetch origin && git pull --ff-only`。
   - 如果是"自动创建 worktree"——这在脚本里已经是 `git worktree add -b`。
   - **追问**：你说的"开工自动化"具体比现在多了什么？如果只是把多个手动步骤串起来，那不过是脚本封装，不算真正的自动化。

2. **"收工自动化"的风险谁来承担？**
   - `finish-task` 如果自动删除 worktree 和 branch，万一用户还在那个 branch 上有未保存的工作？
   - 自动清理 merged branch 会不会误删还没 merge 的 branch？
   - **反驳**：自动化意味着用户失去对关键操作的控制权。对于有破坏性的操作（删除 branch/worktree），"自动化"是一个危险的选择。

3. **用户真的需要这个插件来"自动化"开工/收工吗？**
   - 开工：`git switch -c branch origin/main && mkdir ../wt-branch && cd ../wt-branch` — 熟练用户 10 秒。
   - 收工：`git worktree remove && git branch -d` — 熟练用户 5 秒。
   - **问题**：你的插件在这些场景下节省了多少时间？这个时间投资回收期是多少？如果用户每天只用一次，ROI 是否为正？

---

## 总结质疑

| 方向 | 核心问题 | 最尖锐的挑战 |
|------|---------|-------------|
| select-worktree.sh | 解决谁的痛点？ | 现有交互已经足够，加新层只会增加复杂度 |
| session/branch 关系 | 映射什么，为什么？ | Git worktree 本身就是隔离，再加映射是重复建设 |
| AI 判断层 | 判断错了怎么办？ | 轻量工具引入 LLM 依赖，重量级错误的调试负担谁承担 |
| 半成品不 commit | 对抗 Git 设计？ | 不 commit 就无法享受 Git 的版本管理能力 |
| 开工/收工自动化 | ROI 是否为正？ | 熟练用户手动操作 <10 秒，自动化带来的是风险而非效率 |

---

## 给 proponent 的最后问题

如果这 5 个方向去掉任意 3 个，这个插件还能解决核心问题吗？

如果答案是"还能"，那被去掉的 3 个是不是应该一开始就不在设计里？

如果答案是"不能"，那核心问题到底是什么？
