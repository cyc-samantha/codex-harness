#!/usr/bin/env bash
# Learning GC — Codex SessionStart hook (CX-53). Under the contractor model the
# learning subsystem (observations.jsonl, memory.sqlite, the flock + project-hash
# machinery) lives ONCE in the shared HARNESS_ROOT install; keeping a second copy
# here would create the drift the handoff contract forbids (PLAN.md §3, Phase 3
# note). So this hook REUSES the shared-root GC engine rather than reimplementing
# it: if the Claude-side runner is present it delegates, otherwise it no-ops.
# Always exits 0 — maintenance, never a gate.
# Escape hatch: CLAUDE_DISABLE_LEARNING_GC=1 or CODEX_HARNESS_DISABLE_LEARNING_GC=1.
#
# enforces: AGENTS.md § Runtime Model (shared learning root)

set -uo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${HOOK_DIR}/_lib/harness-paths.sh"
# shellcheck source=/dev/null
source "${HOOK_DIR}/_lib/check-bypass-gate.sh"

check_bypass_gate "CLAUDE_DISABLE_LEARNING_GC" && exit 0
check_bypass_gate "CODEX_HARNESS_DISABLE_LEARNING_GC" && exit 0

SHARED_RUNNER="${HARNESS_ROOT}/hooks/learning-gc.sh"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Delegate only to a DIFFERENT, executable shared-root runner (never recurse
# into this same file when HARNESS_ROOT happens to point back at this repo).
if [[ -x "$SHARED_RUNNER" && "$SHARED_RUNNER" != "$SELF" ]]; then
  exec "$SHARED_RUNNER"
fi

exit 0
