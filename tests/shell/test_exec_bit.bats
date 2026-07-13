#!/usr/bin/env bats
# CX-50 regression pin — the seven executed top-level .codex/hooks/*.sh
# scripts must be committed as executable (mode 100755) in the git index.
# core.filemode=false means the working tree's +x bit does NOT guarantee the
# index entry is executable; hooks.json's launcher is
# `[ -x "$h" ] && exec "$h" || exit 0`, so a fresh clone with a 100644 index
# entry silently degrades enforcement to a no-op instead of failing closed.

load helper

EXECUTED_HOOKS=(
  main-branch-guard.sh
  code-shape-check.sh
  function-body-check.sh
  comment-smell-check.sh
  worktree-reaper.sh
  learning-gc.sh
  codebase-map-rebuild.sh
)

@test "each executed top-level hook is committed with the executable bit (mode 100755)" {
  cd "${BATS_TEST_DIRNAME}/../.."
  local script mode
  for script in "${EXECUTED_HOOKS[@]}"; do
    mode=$(git ls-files -s ".codex/hooks/${script}" | awk '{print $1}')
    [ "$mode" = "100755" ] || {
      echo "expected 100755 for .codex/hooks/${script}, got '${mode}'" >&2
      return 1
    }
  done
}
