#!/usr/bin/env bats
# CX-51 — comment-smell-check PostToolUse hook (WHAT-comment block, WHY allow).

load helper

setup() {
  COMMENT="${HOOKS_DIR}/comment-smell-check.sh"
  make_repo
}

@test "blocks a new WHAT comment that restates code" {
  local f="$REPO_DIR/what.py"
  printf '# increment the counter\nx = x + 1\n' > "$f"
  run bash -c "printf '%s' '$(payload_write "$f")' | '$COMMENT'"
  [ "$status" -eq 2 ]
}

@test "allows a WHY-prefixed comment" {
  local f="$REPO_DIR/why.py"
  printf '# WHY: retry guards against a flaky upstream\nx = x + 1\n' > "$f"
  run bash -c "printf '%s' '$(payload_write "$f")' | '$COMMENT'"
  [ "$status" -eq 0 ]
}

# --- Iron Law 8: fail-closed on unevaluable input ---

@test "fail-closed: blocks a non-JSON payload" {
  run bash -c "printf 'not json' | '$COMMENT'"
  [ "$status" -eq 2 ]
}

@test "fail-closed: blocks an empty payload" {
  run bash -c "printf '' | '$COMMENT'"
  [ "$status" -eq 2 ]
}

teardown() { cxh_cleanup; }
