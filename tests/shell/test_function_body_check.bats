#!/usr/bin/env bats
# CX-51 — function-body-check PostToolUse hook (per-language body cap).

load helper

setup() {
  FUNC="${HOOKS_DIR}/function-body-check.sh"
  make_repo
}

@test "blocks a new over-limit function body" {
  local f="$REPO_DIR/over.py"
  {
    printf 'def big():\n'
    seq 1 20 | sed 's/^/    x = /'
  } > "$f"
  run bash -c "printf '%s' '$(payload_write "$f")' | '$FUNC'"
  [ "$status" -eq 2 ]
}

@test "allows a small function body" {
  local f="$REPO_DIR/ok.py"
  printf 'def small():\n    return 1\n' > "$f"
  run bash -c "printf '%s' '$(payload_write "$f")' | '$FUNC'"
  [ "$status" -eq 0 ]
}

# --- Iron Law 8: fail-closed on unevaluable input ---

@test "fail-closed: blocks a non-JSON payload" {
  run bash -c "printf 'not json' | '$FUNC'"
  [ "$status" -eq 2 ]
}

@test "fail-closed: blocks an empty payload" {
  run bash -c "printf '' | '$FUNC'"
  [ "$status" -eq 2 ]
}

teardown() { cxh_cleanup; }
