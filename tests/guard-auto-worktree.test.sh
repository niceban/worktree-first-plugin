#!/usr/bin/env python3
"""Test suite for guard-auto-worktree.sh — covers all 3 guard scripts.

KEY SCENARIOS tested:
1. PWD == main (real main worktree) → deny dangerous
2. PWD == main, CLAUDE_PROJECT_DIR == task-worktree → allow (worktree session)
3. PWD == task-worktree → allow (normal worktree session)
4. guard-auto-worktree auto-creates worktree at correct path
"""

import subprocess
import sys
import os
import json
import tempfile
import shutil

REPO_ROOT = os.path.join(os.path.dirname(__file__), "..")
GUARD_BASH = os.path.join(REPO_ROOT, "scripts", "guard-bash.sh")
GUARD_MAIN_WRITE = os.path.join(REPO_ROOT, "scripts", "guard-main-write.sh")
GUARD_AUTO_WT = os.path.join(REPO_ROOT, "scripts", "guard-auto-worktree.sh")
FAILED = 0
PASSED = 0


def run_guard(script_path, payload, env_override=None):
    """Run a guard script and return (exit_code, stdout, stderr).

    Uses cwd= from env_override['PWD'] to actually change the subprocess
    working directory (env PWD alone doesn't affect bash's getcwd).
    CLAUDE_PROJECT_DIR is passed via env (not cwd) since it's a custom env var.
    """
    env = os.environ.copy()
    cwd = None
    if env_override:
        if "PWD" in env_override:
            cwd = env_override["PWD"]   # use cwd to set actual working dir
        for k, v in env_override.items():
            env[k] = v
    result = subprocess.run(
        ["bash", script_path],
        input=json.dumps(payload).encode(),
        capture_output=True,
        env=env,
        cwd=cwd,
    )
    return result.returncode, result.stdout.decode(), result.stderr.decode()


def is_denied(stdout):
    return "permissionDecision" in stdout and "deny" in stdout


def is_allowed(stdout):
    return not is_denied(stdout)


def guard_deny(script, cmd, tool_name="Bash", env_override=None, desc=None):
    """Command MUST be denied."""
    global FAILED, PASSED
    payload = {"tool_name": tool_name, "tool_input": {"command": cmd}}
    _, stdout, _ = run_guard(script, payload, env_override)
    if is_denied(stdout):
        PASSED += 1
        print(f"  PASS (denied): {desc or cmd}")
    else:
        FAILED += 1
        print(f"  FAIL (should deny): {desc or cmd}")
        print(f"    stdout: {stdout[:200]}")


def guard_allow(script, cmd, tool_name="Bash", env_override=None, desc=None):
    """Command MUST be allowed."""
    global FAILED, PASSED
    payload = {"tool_name": tool_name, "tool_input": {"command": cmd}}
    _, stdout, _ = run_guard(script, payload, env_override)
    if is_allowed(stdout):
        PASSED += 1
        print(f"  PASS (allowed): {desc or cmd}")
    else:
        FAILED += 1
        print(f"  FAIL (should allow): {desc or cmd}")
        print(f"    stdout: {stdout[:200]}")


def write_allow(script, file_path="/tmp/test.txt", env_override=None, desc=None):
    """Write tool MUST be allowed."""
    global FAILED, PASSED
    payload = {"tool_name": "Write", "tool_input": {"file_path": file_path}}
    _, stdout, _ = run_guard(script, payload, env_override)
    if is_allowed(stdout):
        PASSED += 1
        print(f"  PASS (allowed Write): {desc or file_path}")
    else:
        FAILED += 1
        print(f"  FAIL (should allow Write): {desc or file_path}")
        print(f"    stdout: {stdout[:200]}")


def write_deny(script, file_path="/tmp/test.txt", env_override=None, desc=None):
    """Write tool MUST be denied."""
    global FAILED, PASSED
    payload = {"tool_name": "Write", "tool_input": {"file_path": file_path}}
    _, stdout, _ = run_guard(script, payload, env_override)
    if is_denied(stdout):
        PASSED += 1
        print(f"  PASS (denied Write): {desc or file_path}")
    else:
        FAILED += 1
        print(f"  FAIL (should deny Write): {desc or file_path}")
        print(f"    stdout: {stdout[:200]}")


def auto_create_creates_worktree(script, cmd, env_override, desc):
    """guard-auto-worktree MUST create worktree and return deny+suggestion.

    Returns the actual worktree path if successful, None otherwise.
    """
    global FAILED, PASSED
    payload = {"tool_name": "Bash", "tool_input": {"command": cmd}}
    _, stdout, stderr = run_guard(script, payload, env_override)

    # Extract actual worktree path from stderr (e.g. "auto-worktree: Created worktree at /path/to/wt/slug")
    actual_wt_path = None
    import re
    m = re.search(r'auto-worktree: Created worktree at (/[^\s]+)', stderr)
    if m:
        actual_wt_path = m.group(1)

    # Must return deny JSON with suggestions
    if is_denied(stdout) and "suggestions" in stdout:
        if actual_wt_path:
            PASSED += 1
            print(f"  PASS (auto-created): {desc}")
            print(f"    actual worktree: {actual_wt_path}")
            return actual_wt_path
        else:
            FAILED += 1
            print(f"  FAIL (denied but path not found): {desc}")
            print(f"    stderr: {stderr[:200]}")
            return None
    else:
        FAILED += 1
        print(f"  FAIL (should auto-create worktree): {desc}")
        print(f"    stdout: {stdout[:200]}")
        return None


# =========================================================================
# Detect real git state
# =========================================================================
git_root = subprocess.run(
    ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True
).stdout.strip()

main_branch = subprocess.run(
    ["git", "symbolic-ref", "--short", "HEAD"], capture_output=True, text=True
).stdout.strip()

# Find a non-main worktree if one exists
non_main_worktree = None
result = subprocess.run(
    ["git", "worktree", "list", "--porcelain"], capture_output=True, text=True
)
for line in result.stdout.split("\n"):
    if line.startswith("branch refs/heads/") and "main" not in line:
        # prev line has path
        pass
worktree_paths = []
for line in result.stdout.split("\n"):
    if line.startswith("path "):
        path = line[5:]
        worktree_paths.append(path)

print("=== guard-auto-worktree.sh Test Suite ===")
print(f"Repo root: {git_root}")
print(f"Current branch: {main_branch}")
print(f"Worktree paths: {worktree_paths}")
print()

# =========================================================================
# SCENARIO 1: PWD = main, no CLAUDE_PROJECT_DIR (real main worktree)
# All dangerous operations MUST be denied
# =========================================================================
print("--- Scenario 1: Real main worktree (PWD=main, no CLAUDE_PROJECT_DIR) ---")
env_main_only = {"PWD": git_root}

guard_deny(GUARD_BASH, 'echo "test" > /tmp/test.txt', env_override=env_main_only,
           desc="dangerous redirect")
guard_deny(GUARD_BASH, "git push --force origin feature", env_override=env_main_only,
           desc="bare --force push")
guard_deny(GUARD_BASH, "git reset --hard", env_override=env_main_only,
           desc="git reset --hard")
guard_deny(GUARD_BASH, "git clean -fdx", env_override=env_main_only,
           desc="git clean -fdx")
guard_deny(GUARD_MAIN_WRITE, "", tool_name="Write", env_override=env_main_only,
           desc="Write in main worktree")

# =========================================================================
# SCENARIO 2: PWD = main, CLAUDE_PROJECT_DIR = non-main worktree
# This is the Claude Code session-in-worktree scenario (PWD resets to main
# after each Bash, but CLAUDE_PROJECT_DIR holds the real worktree path)
# All operations MUST be allowed
# =========================================================================
print()
print("--- Scenario 2: Worktree session (PWD=main, CLAUDE_PROJECT_DIR=task) ---")

# Find a non-main worktree to use as CLAUDE_PROJECT_DIR
# If none exists, create a temp one
temp_wt_path = None
temp_wt_branch = None

# Look for existing non-main worktree
existing_wt = None
for wt_path in worktree_paths:
    if wt_path != git_root:
        branch_result = subprocess.run(
            ["git", "-C", wt_path, "symbolic-ref", "--short", "HEAD"],
            capture_output=True, text=True
        )
        branch = branch_result.stdout.strip()
        if branch != "main":
            existing_wt = (wt_path, branch)
            break

if existing_wt:
    task_wt_path, task_wt_branch = existing_wt
    print(f"  Using existing worktree: {task_wt_path} (branch={task_wt_branch})")
else:
    # Create a temp worktree for testing
    temp_wt_path = tempfile.mkdtemp(prefix="wt-test-")
    temp_wt_branch = f"task/test-wt-{os.getpid()}"
    subprocess.run(
        ["git", "worktree", "add", "-b", temp_wt_branch, temp_wt_path, "HEAD"],
        capture_output=True
    )
    task_wt_path = temp_wt_path
    task_wt_branch = temp_wt_branch
    print(f"  Created temp worktree: {task_wt_path} (branch={task_wt_branch})")

env_worktree_session = {
    "PWD": git_root,  # PWD has been reset to main
    "CLAUDE_PROJECT_DIR": task_wt_path,  # but session is in task worktree
}

guard_allow(GUARD_BASH, 'echo "test" > /tmp/test.txt', env_override=env_worktree_session,
            desc="dangerous redirect in worktree session")
guard_allow(GUARD_BASH, "git push --force origin feature", env_override=env_worktree_session,
            desc="bare --force push in worktree session")
guard_allow(GUARD_BASH, "git reset --hard", env_override=env_worktree_session,
            desc="git reset --hard in worktree session")
guard_allow(GUARD_BASH, "git clean -fdx", env_override=env_worktree_session,
            desc="git clean -fdx in worktree session")
write_allow(GUARD_MAIN_WRITE, "/tmp/test.txt", env_override=env_worktree_session,
            desc="Write in worktree session")

# =========================================================================
# SCENARIO 3: PWD = task worktree (normal worktree session, no reset)
# All operations MUST be allowed
# =========================================================================
print()
print("--- Scenario 3: Normal worktree (PWD=task-worktree) ---")
env_normal_wt = {"PWD": task_wt_path}

guard_allow(GUARD_BASH, 'echo "test" > /tmp/test.txt', env_override=env_normal_wt,
            desc="dangerous redirect in normal worktree")
guard_allow(GUARD_BASH, "git push --force origin feature", env_override=env_normal_wt,
            desc="bare --force push in normal worktree")
write_allow(GUARD_MAIN_WRITE, "/tmp/test.txt", env_override=env_normal_wt,
            desc="Write in normal worktree")

# =========================================================================
# SCENARIO 4: guard-auto-worktree.sh auto-creation
# When on main WITHOUT CLAUDE_PROJECT_DIR fallback, MUST create worktree
# =========================================================================
print()
print("--- Scenario 4: guard-auto-worktree auto-creates worktree ---")

env_auto_create = {
    "PWD": git_root,
    "CLAUDE_PROJECT_DIR": git_root,  # No fallback available
}

# The auto-create should create worktree and return deny+suggestion
# auto_create_creates_worktree returns the actual path created
actual_wt_path = auto_create_creates_worktree(
    GUARD_AUTO_WT,
    'echo "test" > /tmp/test.txt',
    env_override=env_auto_create,
    desc="auto-creates worktree for dangerous cmd"
)

# Verify worktree was actually created at the path reported by the guard
if actual_wt_path and os.path.isdir(actual_wt_path):
    print(f"  PASS: worktree directory created at {actual_wt_path}")
    PASSED += 1
    # Cleanup
    subprocess.run(["git", "worktree", "remove", actual_wt_path, "--force"],
                   capture_output=True)
    shutil.rmtree(actual_wt_path, ignore_errors=True)
elif actual_wt_path:
    FAILED += 1
    print(f"  FAIL: guard reported path but directory not found at {actual_wt_path}")
else:
    # auto_create_creates_worktree already reported FAIL
    pass

# Cleanup temp worktree if we created one
if temp_wt_path and os.path.exists(temp_wt_path):
    subprocess.run(["git", "worktree", "remove", temp_wt_path, "--force"],
                    capture_output=True)
    shutil.rmtree(temp_wt_path, ignore_errors=True)

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
