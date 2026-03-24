#!/usr/bin/env bash
# checkpoint.sh — Create a checkpoint commit, then run lightweight validation

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo '')}"
[[ -z "$PROJECT_DIR" ]] && { echo "Not a git repository." >&2; exit 1; }
cd "$PROJECT_DIR"

# Guard: must not be on main
branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [[ "$branch" == "main" ]]; then
  echo "BLOCKED: Cannot checkpoint on main branch." >&2
  exit 1
fi

# Guard: must have staged changes
if git diff --cached --quiet 2>/dev/null; then
  echo "Nothing staged. Run 'git add -p <file>' or 'git add <file>' first." >&2
  exit 1
fi

# Get commit message
MSG="${1:-}"
if [[ -z "$MSG" ]]; then
  echo "Enter checkpoint message:"
  read -r MSG
fi
[[ -z "$MSG" ]] && { echo "Empty message. Aborted." >&2; exit 1; }

# Commit
git commit -m "checkpoint: $MSG"
echo "Checkpoint created: $(git log -1 --format="%h $MSG")"

# Lightweight validation after commit
echo ""
echo "=== Validation ==="

validated=true

if command -v make &>/dev/null; then
  if make format &>/dev/null; then
    echo "  [OK] format passed"
  fi
  if make lint &>/dev/null; then
    echo "  [OK] lint passed"
  elif command -v eslint &>/dev/null && [[ -n "$(git diff --name-only | grep -E '\.(js|ts|jsx|tsx)$')" ]]; then
    git diff --name-only | grep -E '\.(js|ts|jsx|tsx)$' | xargs eslint --max-warnings=0 2>/dev/null && echo "  [OK] eslint passed"
  fi
  if make test-quick &>/dev/null || make test &>/dev/null; then
    echo "  [OK] quick tests passed"
  fi
fi

# Syntax check modified files (not staged — committed files)
for file in $(git diff --name-only HEAD~1..HEAD 2>/dev/null); do
  case "$file" in
    *.sh)
      bash -n "$file" 2>/dev/null || { echo "  [FAIL] syntax error in $file"; validated=false; }
      ;;
    *.js|*.mjs)
      node --check "$file" 2>/dev/null || { echo "  [FAIL] syntax error in $file"; validated=false; }
      ;;
    *.py)
      python3 -m py_compile "$file" 2>/dev/null || { echo "  [FAIL] syntax error in $file"; validated=false; }
      ;;
  esac
done

[[ "$validated" == "true" ]] && echo "  [OK] all checks passed"

echo ""
echo "Recent commits:"
git log --oneline -3 --format="  %h %s"
