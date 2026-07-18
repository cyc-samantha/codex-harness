"""Task Contract validation and identity binding."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


REQUIRED = {
    "task_id",
    "objective",
    "acceptance_criteria",
    "constraints",
    "allowed_scope",
    "prohibited_changes",
    "builder_checks",
    "final_checks",
    "expected_deliverables",
    "risks",
    "repository",
    "base_commit",
}
VERIFICATION_KINDS = {"test", "build", "typecheck", "lint", "static", "inspection", "manual"}


class ContractError(Exception):
    pass


def canonical(value: dict) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value: dict) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def load_contract(path: Path) -> dict:
    try:
        value = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError("INVALID_TASK_CONTRACT") from error
    validate_contract(value)
    return value


def validate_contract(value: dict) -> None:
    if invalid_contract_shape(value) or invalid_identity(value):
        raise ContractError("INVALID_TASK_CONTRACT")
    validate_criteria(value["acceptance_criteria"])
    validate_checks(value["builder_checks"])
    validate_checks(value["final_checks"])


def invalid_contract_shape(value: dict) -> bool:
    if not isinstance(value, dict) or REQUIRED - value.keys():
        return True
    collections = ("acceptance_criteria", "constraints", "allowed_scope", "prohibited_changes",
                   "builder_checks", "final_checks", "expected_deliverables", "risks")
    lists_valid = all(isinstance(value[field], list) for field in collections)
    return not lists_valid or invalid_patterns(value) or not value["acceptance_criteria"] or not value["allowed_scope"]


def invalid_patterns(value: dict) -> bool:
    return any(not isinstance(item, str) for field in ("allowed_scope", "prohibited_changes") for item in value[field])


def invalid_identity(value: dict) -> bool:
    task_valid = isinstance(value["task_id"], str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", value["task_id"])
    commit_valid = isinstance(value["base_commit"], str) and re.fullmatch(r"[0-9a-f]{40,64}", value["base_commit"])
    strings_valid = all(isinstance(value[field], str) and value[field] for field in ("objective", "repository"))
    return not task_valid or not commit_valid or not strings_valid


def validate_criteria(criteria: list[dict]) -> None:
    ids = set()
    for criterion in criteria:
        validate_criterion(criterion, ids)


def validate_checks(checks: list[dict]) -> None:
    if not checks or not all(valid_check(command) for command in checks):
        raise ContractError("INVALID_TASK_CONTRACT")


def valid_check(check: dict) -> bool:
    if not isinstance(check, dict) or not isinstance(check.get("command"), str) or not check["command"]:
        return False
    timeout = check.get("timeout_seconds", 600)
    return isinstance(timeout, int) and timeout > 0


def validate_criterion(criterion: dict, ids: set[str]) -> None:
    if not criterion_shape_valid(criterion):
        raise ContractError("INVALID_TASK_CONTRACT")
    if criterion["id"] in ids or not criterion["verification"]:
        raise ContractError("INVALID_TASK_CONTRACT")
    if invalid_verification(criterion["verification"]):
        raise ContractError("INVALID_TASK_CONTRACT")
    ids.add(criterion["id"])

def criterion_shape_valid(criterion: dict) -> bool:
    if not isinstance(criterion, dict) or {"id", "statement", "verification"} - criterion.keys():
        return False
    strings_valid = all(isinstance(criterion[field], str) and criterion[field] for field in ("id", "statement"))
    return strings_valid and isinstance(criterion["verification"], list)


def invalid_verification(evidence: list[dict]) -> bool:
    return any(not isinstance(item, dict) or item.get("kind") not in VERIFICATION_KINDS
               or not isinstance(item.get("evidence"), str) or not item["evidence"] for item in evidence)
