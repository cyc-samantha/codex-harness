#!/usr/bin/env bats
# CX-51 — code-shape-check PostToolUse hook (whole-file line cap).

load helper

setup() {
  SHAPE="${HOOKS_DIR}/code-shape-check.sh"
  make_repo
}

@test "blocks a source file over the line cap" {
  local f="$REPO_DIR/big.py"
  seq 1 350 | sed 's/^/x = /' > "$f"
  run bash -c "printf '%s' '$(payload_write "$f")' | '$SHAPE'"
  [ "$status" -eq 2 ]
}

@test "allows a source file under the line cap" {
  local f="$REPO_DIR/small.py"
  printf 'x = 1\ny = 2\n' > "$f"
  run bash -c "printf '%s' '$(payload_write "$f")' | '$SHAPE'"
  [ "$status" -eq 0 ]
}

@test "ignores non-source files" {
  local f="$REPO_DIR/notes.md"
  seq 1 350 > "$f"
  run bash -c "printf '%s' '$(payload_write "$f")' | '$SHAPE'"
  [ "$status" -eq 0 ]
}

# --- Iron Law 8: fail-closed on unevaluable input ---

@test "fail-closed: blocks a non-JSON payload" {
  run bash -c "printf 'not json' | '$SHAPE'"
  [ "$status" -eq 2 ]
}

@test "fail-closed: blocks an empty payload" {
  run bash -c "printf '' | '$SHAPE'"
  [ "$status" -eq 2 ]
}

teardown() { cxh_cleanup; }
