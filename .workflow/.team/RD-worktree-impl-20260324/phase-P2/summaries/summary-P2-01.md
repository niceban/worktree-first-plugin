# Summary P2-01: AI Checkpoint Advisor

## Task ID
P2-01

## Status
COMPLETED

## Goal
在 checkpoint 之前调用 LLM 分析 staged diff，给出"是否值得 commit"的判断 + 理由

## Implementation

### Modified Files
- `/Users/c/auto-git/worktree-first-plugin/scripts/checkpoint.sh`

### Changes Made
1. Added `_ai_advisor()` function (lines 27-77):
   - Gets staged diff via `git diff --cached`
   - Calls `ccw cli -p "..." --tool gemini --mode analysis` to analyze diff
   - Parses JSON response for judgment, reason, and suggested_message
   - Falls back to rule-based suggestion if LLM fails

2. Modified commit message flow (lines 128-149):
   - Calls AI advisor before generating suggestion
   - Shows AI recommendation if available
   - Falls back to rule-based (P1-02) if LLM unavailable

### Integration
- Existing `_generate_suggestion()` (P1-02 rule-based) remains as fallback
- Metadata update unchanged
- Validation flow unchanged

### LLM Integration
- Tool: `ccw cli --tool gemini --mode analysis`
- Input: staged diff content
- Expected output: JSON with `judgment`, `reason`, `suggested_message`
- Graceful fallback: if LLM fails or returns invalid JSON, uses rule-based suggestion

## Verification
- Syntax check: PASSED (`bash -n checkpoint.sh`)
- Backward compatibility: YES (existing rule-based fallback preserved)
