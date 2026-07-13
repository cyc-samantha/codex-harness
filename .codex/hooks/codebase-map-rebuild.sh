#!/usr/bin/env bash
# Codebase-map Rebuild — Codex SessionStart hook (CX-53). DEFERRED STUB.
#
# The Claude harness hooks/codebase-map-rebuild.sh drives a tree-sitter +
# PageRank generator invoked as `python3 -m codebase_map.cli build <root> <cache>`
# (see hooks/_lib/codebase-map-common.sh). That generator is a Claude-side
# subsystem NOT ported to codex-harness (PLAN.md §2 "Codebase-map auto-generation
# → No native primitive → Port the tree-sitter + PageRank generator" — deferred
# with the memory/learning subsystems under the Phase 7 contractor pivot). Wiring
# this hook to a generator that does not exist here would break every session
# start, so it is intentionally a no-op stub.
#
# When (if) the generator is ported, replace this body with the delegation form
# used by learning-gc.sh, or vendor the generator under a codex-harness subtree.
# Always exits 0 — maintenance, never a gate.
#
# enforces: AGENTS.md § Runtime Model (deferred subsystem)

set -uo pipefail
exit 0
