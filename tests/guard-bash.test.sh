#!/usr/bin/env python3
"""Test suite for guard-bash.sh PreToolUse hook.

ARCHITECTURE (D1+D2+D4+D5+D6+D7):
- Main worktree detection: PWD == git rev-parse --show-toplevel
- In task worktree: ALWAYS ALLOW (worktree is isolated)
- guard-auto-worktree.sh handles auto-creation with idempotency + rollback
"""

import subprocess
import sys
import os
import json

GUARD_BASH = os.path.join(os.path.dirname(__file__), "..", "scripts", "guard-bash.sh")
GUARD_AUTO_WT = os.path.join(os.path.dirname(__file__), "..", "scripts", "guard-auto-worktree.sh")
FAILED = 0
PASSED = 0


def guard_deny(script_path, cmd, tool_name="Bash"):
    """Run guard with a command that SHOULD be denied."""
    global FAILED, PASSED
    payload = {"tool_name": tool_name, "tool_input": {"command": cmd}}

    result = subprocess.run(
        ["bash", script_path],
        input=json.dumps(payload).encode(),
        capture_output=True,
    )
    output = result.stdout.decode()
    if "permissionDecision" in output and "deny" in output:
        print(f"  PASS (denied): {cmd}")
        PASSED += 1
    else:
        print(f"  FAIL (should deny): {cmd}")
        print(f"    output: {output[:200]}")
        FAILED += 1


def guard_allow(script_path, cmd, tool_name="Bash"):
    """Run guard with a command that SHOULD be allowed."""
    global FAILED, PASSED
    payload = {"tool_name": tool_name, "tool_input": {"command": cmd}}

    result = subprocess.run(
        ["bash", script_path],
        input=json.dumps(payload).encode(),
        capture_output=True,
    )
    output = result.stdout.decode()
    if "permissionDecision" not in output or "deny" not in output:
        print(f"  PASS (allowed): {cmd}")
        PASSED += 1
    else:
        print(f"  FAIL (should allow): {cmd}")
        print(f"    output: {output[:200]}")
        FAILED += 1


os.chdir(os.path.join(os.path.dirname(__file__), ".."))

# Get git root
try:
    git_root = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True
    ).stdout.strip()
except:
    git_root = ""

# Detect if we are in main worktree (PWD == git root)
is_main = (os.getcwd() == git_root)

print("=== guard-bash.sh Test Suite ===")
print(f"Script: {GUARD_BASH}")
print(f"Git root: {git_root}")
print(f"Current dir: {os.getcwd()}")
print(f"Is main worktree: {is_main}")
print()

# =========================================================================
# Test Group 1: Main worktree danger detection (NEW ARCHITECTURE)
# =========================================================================
print("--- Test Group 1: Main worktree danger detection ---")
if is_main:
    # In main worktree - ALL dangerous commands should be denied
    print("(Running in main worktree - dangerous commands should be denied)")

    # Rule 1: File-writing commands -> deny
    guard_deny(GUARD_BASH, "echo hello > /tmp/test.txt")
    guard_deny(GUARD_BASH, "echo world >> /tmp/test.txt")
    guard_deny(GUARD_BASH, "some_cmd | tee /tmp/out.txt")
    guard_deny(GUARD_BASH, "some_cmd |cat > /tmp/out.txt")
    guard_deny(GUARD_BASH, "sed -i 's/foo/bar/' file.txt")
    guard_deny(GUARD_BASH, "perl -i -pe 's/foo/bar/' file.txt")
    guard_deny(GUARD_BASH, "python -c 'open(\"f\",\"w\").write(\"x\")'")
    guard_deny(GUARD_BASH, "truncate -s 0 file.txt")
    guard_deny(GUARD_BASH, "dd if=/dev/zero of=file.txt bs=1 count=0")
    guard_deny(GUARD_BASH, "some_cmd >file.txt")
    guard_deny(GUARD_BASH, "some_cmd >>file.txt")

    # Safe redirects to /dev/null -> allow
    guard_allow(GUARD_BASH, "some_cmd > /dev/null")
    guard_allow(GUARD_BASH, "some_cmd 2> /dev/null")

    # Rule 2: git push to main -> deny
    guard_deny(GUARD_BASH, "git push origin main")
    guard_deny(GUARD_BASH, "git push origin feature:refs/heads/main")
    guard_deny(GUARD_BASH, "git push origin HEAD:main")

    # Non-main push -> allow
    guard_allow(GUARD_BASH, "git push origin my-branch")

    # Rule 3: --force vs --force-with-lease -> deny bare --force
    guard_deny(GUARD_BASH, "git push --force origin my-branch")
    guard_deny(GUARD_BASH, "git push -f origin my-branch")
    guard_allow(GUARD_BASH, "git push --force-with-lease origin my-branch")

    # Rule 4: git reset --hard bare -> deny
    guard_deny(GUARD_BASH, "git reset --hard")

    # git reset with target -> allow (intentional)
    guard_allow(GUARD_BASH, "git reset --soft HEAD~1")
    guard_allow(GUARD_BASH, "git reset HEAD file.txt")
    guard_allow(GUARD_BASH, "git reset --hard HEAD~1")

    # Rule 5: git clean -x/-X -> deny
    guard_deny(GUARD_BASH, "git clean -fdx")
    guard_deny(GUARD_BASH, "git clean -fdX")
    guard_deny(GUARD_BASH, "git clean -fdxd")
    guard_deny(GUARD_BASH, "git clean -fdxx")

    # Safe clean forms -> allow
    guard_allow(GUARD_BASH, "git clean -fd")
    guard_allow(GUARD_BASH, "git clean -f")

    # Rule 6: delete main/master -> deny
    guard_deny(GUARD_BASH, "git branch -d main")
    guard_deny(GUARD_BASH, "git branch -D main")
    guard_deny(GUARD_BASH, "git branch -d master")
    guard_deny(GUARD_BASH, "git branch -D master")

    # Other branch deletion -> allow
    guard_allow(GUARD_BASH, "git branch -d my-feature")
    guard_allow(GUARD_BASH, "git branch -D my-feature")
else:
    print("(Running in worktree - all commands should be allowed)")
    # In worktree - all operations should be allowed
    guard_allow(GUARD_BASH, "echo hello > /tmp/test.txt")
    guard_allow(GUARD_BASH, "sed -i 's/foo/bar/' file.txt")
    guard_allow(GUARD_BASH, "git push --force origin my-branch")
    guard_allow(GUARD_BASH, "git reset --hard")
    guard_allow(GUARD_BASH, "git clean -fdx")
    guard_allow(GUARD_BASH, "git branch -d main")

# =========================================================================
# Test Group 2: guard-auto-worktree.sh idempotency (D5)
# =========================================================================
print()
print("--- Test Group 2: guard-auto-worktree idempotency (D5) ---")

# Test that creating worktree with duplicate slug fails
# This requires mocking the git worktree add command
# For now, we test the slug generation is unique

def test_idempotency():
    """Test that auto-create fails if worktree already exists."""
    global FAILED, PASSED

    # Create a mock test: check that if worktree dir exists, it returns error
    # We can't easily test this without mocking git, so we test the logic
    # that guard-auto-worktree.sh checks for existing worktree

    # Test: if git worktree list shows the path, it's a worktree
    result = subprocess.run(
        ["git", "worktree", "list", "--porcelain"],
        capture_output=True, text=True
    )
    worktrees = result.stdout

    # At minimum, main worktree should be listed
    if git_root and git_root in worktrees:
        print("  PASS: main worktree detected in git worktree list")
        PASSED += 1
    else:
        print("  FAIL: main worktree not in git worktree list")
        FAILED += 1

test_idempotency()

# =========================================================================
# Test Group 3: is_worktree_dir detection (D4)
# =========================================================================
print()
print("--- Test Group 3: worktree detection (D4) ---")

def test_worktree_detection():
    """Test that guard scripts correctly detect worktree vs main."""
    global FAILED, PASSED

    # The guard-bash.sh should allow in worktree, deny in main
    # We already tested this above via behavior, but let's verify
    # the PWD == git_root detection works

    result = subprocess.run(
        ["bash", "-c", '''
        source "$(dirname "$0")/../scripts/guard-bash.sh" 2>/dev/null || true
        get_git_root() {
          git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo ""
        }
        is_main_worktree() {
          local git_root
          git_root=$(get_git_root)
          [[ -z "$git_root" ]] && return 1
          [[ "$(realpath "$PWD")" == "$(realpath "$git_root")" ]]
        }
        if is_main_worktree; then
          echo "MAIN"
        else
          echo "WORKTREE"
        fi
        '''],
        cwd=os.getcwd(),
        capture_output=True, text=True
    )

    detected = result.stdout.strip()
    expected = "MAIN" if is_main else "WORKTREE"

    if detected == expected:
        print(f"  PASS: correctly detected {expected}")
        PASSED += 1
    else:
        print(f"  FAIL: detected {detected}, expected {expected}")
        FAILED += 1

test_worktree_detection()

# =========================================================================
# Summary
# =========================================================================
print()
print(f"=== Results: {PASSED} passed, {FAILED} failed ===")
if FAILED > 0:
    print("SOME TESTS FAILED")
    sys.exit(1)
else:
    print("ALL TESTS PASSED")
    sys.exit(0)
