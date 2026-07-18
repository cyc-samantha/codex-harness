"""Independent Builder evidence checks."""

from __future__ import annotations

import subprocess
from pathlib import Path

from builder_guardian_state import StateError, git


def target_descends(repo: Path, base: str, target: str) -> bool:
    result = subprocess.run(["git", "-C", str(repo), "merge-base", "--is-ancestor", base, target])
    return result.returncode == 0 and base != target


def branch_matches(worktree: Path, branch: str) -> bool:
    return git(worktree, "branch", "--show-current") == branch


def validate_test_paths(worktree: Path, tests: list[str], files: list[str]) -> None:
    if not tests or not set(tests) <= set(files):
        raise StateError("BLOCKED: changed tests are not in the review target")
    if any(not (worktree / path).is_file() for path in tests):
        raise StateError("BLOCKED: changed test path is missing")


def execute_check(check: dict, worktree: Path) -> dict:
    try:
        result = subprocess.run(["bash", "-lc", check["command"]], cwd=worktree, timeout=check.get("timeout_seconds", 600))
        return {"command": check["command"], "passed": result.returncode == 0}
    except subprocess.TimeoutExpired:
        return {"command": check["command"], "passed": False}


def execute_builder_checks(checks: list[dict], worktree: Path) -> list[dict]:
    results = [execute_check(check, worktree) for check in checks]
    if any(not result["passed"] for result in results):
        raise StateError("BLOCKED: Builder validation failed")
    if git(worktree, "status", "--porcelain"):
        raise StateError("BLOCKED: Builder checks changed the review target")
    return results
