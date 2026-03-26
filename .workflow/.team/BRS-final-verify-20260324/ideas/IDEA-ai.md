# AI Fallback Chain Analysis

## Script: checkpoint.sh
## Angle: ai_fallback_chain

---

## 1. ccw cli 不存在时的 Fallback

**Location**: `_ai_advisor()` (line 44-50)

```bash
ccw_output=$(timeout 30 ccw cli -p "..." --tool gemini --mode write 2>/dev/null) || true
```

| Fallback Layer | Behavior |
|----------------|----------|
| `ccw` not found | `\|\| true` 捕获错误，ccw_output 保持为空字符串 |
| 后续检查 | `-n "$ccw_output"` 为空，进入 `_generate_suggestion()` 规则生成 |

**结论**: fallback 链条存在且正确，ccw 不存在时优雅降级到规则建议。

---

## 2. LLM 返回空输出时的 Fallback

**Location**: `_ai_advisor()` (line 55)

```bash
if [[ -n "$ccw_output" ]]; then
    # parse JSON...
fi
# falls through to echo "AI Advisor: LLM analysis unavailable"
```

**结论**: 逻辑正确。LLM 返回空输出时跳过解析，直接走规则 fallback。

---

## 3. JSON 解析失败时的 Fallback

**Location**: `_ai_advisor()` (line 56-68)

双层 fallback：
1. `jq` 可用时：用 `jq -r '.judgment // empty'` 解析
2. `jq` 不可用时：用 `sed + grep -oP` 提取字段

```bash
if command -v jq &>/dev/null; then
    judgment=$(echo "$ccw_output" | jq -r '.judgment // empty' 2>/dev/null || echo "")
else
    # strip markdown code blocks, then grep
    json_text=$(echo "$ccw_output" | sed 's/```json//g;s/```//g' | tr -d '\n')
    judgment=$(echo "$json_text" | grep -oP '"judgment"[[:space:]]*:[[:space:]]*"\K[^"]+' || echo "")
fi
```

**结论**: jq 主路径 + grep 备用路径，fallback 设计充分。

**潜在风险**: 如果 LLM 返回的 JSON 有 markdown code fences，但 `sed` 替换失败（比如有多余的 ```），grep 也会失败，最终 judgment 为空。后续检查 `[[ -n "$judgment" && -n "$reason" ]]` 失败，走规则 fallback。

---

## 4. Timeout 30s 是否合理

**场景分析：5000 行 diff**

实测参考（ccw cli gemini）：5000 行 diff 的 token 量约 ~15-25K tokens，30s timeout 在以下条件下可能不够：

| 因素 | 耗时估算 |
|------|---------|
| 网络延迟（到 Google AI API） | 2-5s |
| 模型推理时间（~20K tokens） | 5-15s |
| 响应传输 | 1-3s |
| **总计** | **8-23s** |

30s 在正常网络下勉强够用，但以下情况会超时：
- 网络抖动
- diff 包含大量重复代码（模型推理更慢）
- 系统负载高

**checkpoint.sh 没有显式处理 timeout**（只有 `|| true` 捕获所有错误）。timeout 退出码 124 会被 `|| true` 静默吞噬，等同于 ccw 不存在，行为正确但无法区分。

**prepare-push.sh** 显式处理了 timeout (exit_code=124)，行为更清晰。

**建议**:
- 保持 30s default，实际够用
- 但考虑区分 timeout 和 ccw-not-found：两者都应走 fallback，但 log 信息应不同
- 可考虑在 prompt 中加 " Respond briefly if diff is large" 以降低推理耗时

---

## 5. jq 在 macOS 上是否默认存在

**实测**：
```bash
# macOS 默认 shell (bash/zsh) 不带 jq
$ command -v jq
# (无输出，jq 不在 PATH)

# 常见安装途径：
# - Homebrew: brew install jq
# - Anaconda: jq 在 /opt/anaconda3/bin/jq (该系统有)
```

**对功能的影响评估**：

| Script | jq 用途 | 无 jq 时的行为 |
|--------|---------|---------------|
| checkpoint.sh (metadata update) | `_meta_update_checkpoint()` 更新 `.dirty=false` | **功能降级**：metadata 不更新，worktree 状态不准确 |
| prepare-push.sh | `_ai_assessment()` 读取 checkpoint history | **功能降级**：checkpoint history 显示 "unavailable"，AI 评估缺少上下文 |

**严重程度**：
- checkpoint.sh 中 `_meta_update_checkpoint()` 如果 jq 失败，静默跳过后续 `rm -f "${meta_file}.tmp"` 和 `echo "  [OK] metadata updated"`，用户不知道 metadata 没更新。
- prepare-push.sh 中 `jq -r '.checkpoints[-5:] | reverse | join(" | ")'` 失败时 checkpoint_history="unavailable"，只是缺少历史展示，不阻塞功能。

**建议**：在两个脚本开头加 jq 检查：
```bash
if ! command -v jq &>/dev/null; then
    echo "WARNING: jq not found. Some features may be degraded." >&2
    echo "Install with: brew install jq" >&2
fi
```

---

## Summary

| Fallback 场景 | checkpoint.sh | prepare-push.sh |
|---------------|---------------|-----------------|
| ccw cli 不存在 | OK (empty string -> rule) | OK (ccw check -> skip) |
| LLM 返回空 | OK (empty check -> rule) | OK (empty check -> skip) |
| JSON parse 失败 | OK (jq + grep dual path) | N/A (只做文本展示) |
| timeout 30s | OK (被 \|\| true 捕获，但无区分 log) | OK (显式处理 exit_code=124) |
| jq 缺失 | **RISK**: metadata update silently fails | **LOW RISK**: checkpoint history shows "unavailable" |
