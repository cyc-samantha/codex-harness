#!/usr/bin/env bash
# Canonical runtime-state + code roots for the shared contractor kit (CX-50/53).
# Both harnesses point at ONE data root (AGENTS.md § Runtime Model), so ported
# hooks resolve state against ${HARNESS_DATA:-$HOME/.claude}, never a repo-local
# copy. HARNESS_ROOT is the shared *code* install (used only to reuse the
# Claude-side learning engine — see learning-gc.sh); it defaults to the same
# root so a standalone Codex checkout still resolves sanely.
[[ -n "${_HARNESS_PATHS_LOADED:-}" ]] && return 0
_HARNESS_PATHS_LOADED=1
HARNESS_DATA="${HARNESS_DATA:-${CLAUDE_PLUGIN_DATA:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}}"
HARNESS_ROOT="${HARNESS_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}}"
[[ "$HARNESS_DATA" = /* ]] || { echo "harness-paths: HARNESS_DATA must be absolute" >&2; return 1; }
[[ "$HARNESS_ROOT" = /* ]] || { echo "harness-paths: HARNESS_ROOT must be absolute" >&2; return 1; }
export HARNESS_DATA HARNESS_ROOT
