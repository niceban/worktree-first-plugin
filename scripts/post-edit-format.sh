#!/usr/bin/env bash
# post-edit-format.sh — Auto-format and check after Edit/Write/MultiEdit
# Called on PostToolUse hook — changes are in working tree (not staged yet)

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$PROJECT_DIR" ]] && exit 0

cd "$PROJECT_DIR"

# Get list of files modified in the last Edit/Write operation
# PostToolUse fires AFTER the edit, so git diff shows the uncommitted changes
changed_files=$(git diff --name-only 2>/dev/null || true)
[[ -z "$changed_files" ]] && exit 0

format_run=0

# Run format on the changed files
if command -v make &>/dev/null && make -n format &>/dev/null; then
  make format 2>/dev/null && format_run=1
elif command -v gofmt &>/dev/null && echo "$changed_files" | grep -q '\.go$'; then
  echo "$changed_files" | grep '\.go$' | xargs gofmt -w 2>/dev/null && format_run=1
elif command -v prettier &>/dev/null; then
  echo "$changed_files" | grep -E '\.(js|jsx|ts|tsx|json|css|html|md)$' | xargs prettier --write 2>/dev/null && format_run=1
elif command -v black &>/dev/null && echo "$changed_files" | grep -q '\.py$'; then
  echo "$changed_files" | grep '\.py$' | xargs black 2>/dev/null && format_run=1
fi

# Check whitespace in working tree (not staged — PostToolUse already applied the edit)
if git diff --check 2>/dev/null; then
  :
else
  echo "WARNING: whitespace errors in working tree changes." >&2
fi

# Syntax check on changed files
for file in $changed_files; do
  case "$file" in
    *.sh)
      bash -n "$file" 2>/dev/null || echo "SYNTAX ERROR in $file" >&2
      ;;
    *.js|*.mjs)
      node --check "$file" 2>/dev/null || echo "SYNTAX ERROR in $file" >&2
      ;;
    *.py)
      python3 -m py_compile "$file" 2>/dev/null || echo "SYNTAX ERROR in $file" >&2
      ;;
  esac
done

[[ "$format_run" -eq 1 ]] && echo "Auto-format applied to changed files."
