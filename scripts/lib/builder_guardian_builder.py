"""Isolated Builder dispatch with a handoff-only output boundary."""

from __future__ import annotations

import json
import os
import re
import subprocess
import uuid
from pathlib import Path

from builder_guardian_state import PipelineState, StateError, git


def safe_task_id(task_id: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._-]", "-", task_id)
    if not value or value.startswith("-"):
        raise StateError("INVALID_TASK_CONTRACT")
    return value


def builder_prompt(state: PipelineState, session_id: str, worktree: Path) -> str:
    return f"""You are the Builder Codex for task {state.data['task_id']}.
Read the immutable Task Contract at {state.directory / 'contract.json'}.
Work only in {worktree} on its existing feature branch. Follow repository
instructions and TDD. Do not alter the Task Contract, issue a Guardian verdict,
or create READY_TO_SHIP evidence. Run every Builder-stage check, commit the fixed
target, and return only the required Builder handoff JSON. Builder session ID:
{session_id}
"""


def create_worktree(state: PipelineState) -> tuple[Path, str]:
    worktree = state.repo / ".claude" / "worktrees" / f"builder-{safe_task_id(state.data['task_id'])}"
    if worktree.exists():
        return existing_worktree(state, worktree)
    branch = f"codex/{safe_task_id(state.data['task_id'])}"
    add_worktree(state, worktree, branch)
    return worktree, branch


def existing_worktree(state: PipelineState, worktree: Path) -> tuple[Path, str]:
    if state.data.get("worktree") != str(worktree):
        raise StateError("BLOCKED: Builder worktree already exists")
    return worktree, state.data["branch"]


def add_worktree(state: PipelineState, worktree: Path, branch: str) -> None:
    worktree.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(["git", "-C", str(state.repo), "worktree", "add", str(worktree),
                             "-b", branch, state.contract["base_commit"]], capture_output=True, text=True)
    if result.returncode != 0:
        raise StateError("BLOCKED: Builder worktree creation failed")


def builder_command(state: PipelineState, session_id: str, worktree: Path, output: Path) -> list[str]:
    codex = os.environ.get("CODEX_BIN", "codex")
    schema = Path(__file__).with_name("schemas") / "builder-handoff.schema.json"
    return [codex, "exec", "--ephemeral", "--sandbox", "workspace-write", "--cd", str(worktree),
            "--output-schema", str(schema), "--output-last-message", str(output),
            builder_prompt(state, session_id, worktree)]


def complete_builder(state: PipelineState, worktree: Path, branch: str, session_id: str, output: Path) -> None:
    package = json.loads(output.read_text())
    package.update({"task_id": state.data["task_id"], "builder_session_id": session_id, "worktree": str(worktree), "branch": branch, "repository": str(state.repo)})
    invalid = git(worktree, "status", "--porcelain") or git(worktree, "rev-parse", "HEAD") != package.get("review_target")
    if invalid:
        raise StateError("BLOCKED: Builder target mismatch")
    state.accept_handoff(package)


def run_builder(state: PipelineState) -> None:
    if state.data["status"] not in {"CONTRACT_READY", "BUILDING"}:
        raise StateError("BLOCKED: Builder cannot run in current state")
    worktree, branch = create_worktree(state)
    session_id = str(uuid.uuid4())
    state.transition("BUILDING", "builder", "isolated Builder started", session_id)
    invoke_builder(state, worktree, branch, session_id)


def invoke_builder(state: PipelineState, worktree: Path, branch: str, session_id: str) -> None:
    output = state.directory / "builder-output.json"
    result = subprocess.run(builder_command(state, session_id, worktree, output), text=True, capture_output=True)
    if result.returncode != 0 or not output.exists():
        block_builder(state, session_id)
    complete_builder(state, worktree, branch, session_id, output)


def block_builder(state: PipelineState, session_id: str) -> None:
    state.transition("BLOCKED", "builder", "Builder invocation failed", session_id)
    raise StateError("BLOCKED: Builder failed")
