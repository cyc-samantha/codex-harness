#!/usr/bin/env bats
# CX-50 — main-branch-guard PreToolUse hook.

load helper

setup() { GUARD="${HOOKS_DIR}/main-branch-guard.sh"; }

@test "blocks bare 'git checkout' at repo root" {
  make_repo
  run bash -c "cd '$REPO_DIR' && printf '%s' '$(payload_bash "git checkout -b topic")' | '$GUARD'"
  [ "$status" -eq 2 ]
}

@test "allows 'git -C <worktree> checkout' delegation form" {
  make_repo_with_worktree
  run bash -c "cd '$REPO_DIR' && printf '%s' '$(payload_bash "git -C $WORKTREE_DIR checkout -b topic")' | '$GUARD'"
  [ "$status" -eq 0 ]
}

@test "allows a non-HEAD-mutating command" {
  make_repo
  run bash -c "cd '$REPO_DIR' && printf '%s' '$(payload_bash "git status")' | '$GUARD'"
  [ "$status" -eq 0 ]
}

@test "ignores non-Bash tool payloads" {
  run bash -c "printf '%s' '$(payload_write /tmp/x.py)' | '$GUARD'"
  [ "$status" -eq 0 ]
}

# --- wrapper-bypass hardening (security-review MEDIUM finding) ---

@test "blocks 'command git checkout' wrapper bypass at repo root" {
  make_repo
  run bash -c "cd '$REPO_DIR' && printf '%s' '$(payload_bash "command git checkout -b topic")' | '$GUARD'"
  [ "$status" -eq 2 ]
}

@test "blocks 'env git checkout' wrapper bypass at repo root" {
  make_repo
  run bash -c "cd '$REPO_DIR' && printf '%s' '$(payload_bash "env git checkout -b topic")' | '$GUARD'"
  [ "$status" -eq 2 ]
}

# --- Iron Law 8: fail-closed on unevaluable input ---

@test "fail-closed: blocks an empty payload" {
  run bash -c "printf '' | '$GUARD'"
  [ "$status" -eq 2 ]
}

@test "fail-closed: blocks a non-JSON payload" {
  run bash -c "printf 'not json at all' | '$GUARD'"
  [ "$status" -eq 2 ]
}

teardown() { cxh_cleanup; }
