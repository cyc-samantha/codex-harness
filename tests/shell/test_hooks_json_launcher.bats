#!/usr/bin/env bats
# CX-50 — hooks.json PreToolUse launcher must warn loudly (stderr) instead of
# silently no-op'ing when main-branch-guard.sh is missing or non-executable.
# security-review MEDIUM: `[ -x "$h" ] && exec "$h" || exit 0` gave no signal
# that the gate had gone inert.

load helper

setup() {
  HOOKS_JSON="${BATS_TEST_DIRNAME}/../../.codex/hooks/hooks.json"
  LAUNCHER=$(jq -r '.hooks.PreToolUse[0].hooks[0].args[1]' "$HOOKS_JSON")
  FAKE_ROOT="$(cxh_mktemp_dir)"
  mkdir -p "$FAKE_ROOT/.codex/hooks"
}

teardown() {
  [[ -n "${FAKE_ROOT:-}" ]] && rm -rf "$FAKE_ROOT"
}

@test "PreToolUse launcher warns on stderr when script is non-executable" {
  cp "${BATS_TEST_DIRNAME}/../../.codex/hooks/main-branch-guard.sh" \
     "$FAKE_ROOT/.codex/hooks/main-branch-guard.sh"
  chmod 644 "$FAKE_ROOT/.codex/hooks/main-branch-guard.sh"
  run env CODEX_PROJECT_ROOT="$FAKE_ROOT" bash -c "$LAUNCHER" </dev/null
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "PreToolUse launcher warns on stderr when script is missing" {
  run env CODEX_PROJECT_ROOT="$FAKE_ROOT" bash -c "$LAUNCHER" </dev/null
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "PreToolUse launcher stays silent and runs the guard when executable" {
  cp "${BATS_TEST_DIRNAME}/../../.codex/hooks/main-branch-guard.sh" \
     "$FAKE_ROOT/.codex/hooks/main-branch-guard.sh"
  chmod 755 "$FAKE_ROOT/.codex/hooks/main-branch-guard.sh"
  run env CODEX_PROJECT_ROOT="$FAKE_ROOT" bash -c "$LAUNCHER" <<< "$(payload_bash "git status")"
  [ "$status" -eq 0 ]
}
