# Hook Trust — one-time step on every fresh clone (CX-04)

Codex CLI requires reviewing and trusting non-managed `command`-type hooks
before it will run them. Unlike the Claude harness — whose hooks are
implicitly trusted by living under `~/.claude/hooks/`, a directory the user
already controls — a fresh `codex-harness` checkout ships hooks *inside the
repo* (`.codex/hooks/hooks.json`), and Codex treats them as untrusted until
you approve them.

## The flow on a fresh clone

1. Clone the repo and start `codex` at the repo root.
2. Run `/hooks` in the CLI. Codex lists every hook registered from
   `.codex/hooks/hooks.json` with its event (`PreToolUse`, `PostToolUse`,
   `SessionStart`, ...) and the command it executes.
3. **Read every script before trusting it.** Each entry points at a shell
   script in this directory (`.codex/hooks/*.sh`). Open it. This is the only
   review standing between you and an unreviewed script executing on every
   tool call.
4. Trust the reviewed entries. Until you do, the enforcement layer (shape
   rules, main-branch guard, observation capture) is silently inert — the
   harness degrades to advisory-only without telling you.

## Why this file exists

This is a genuine UX regression versus the Claude harness (PLAN.md §7):
there, hook trust is implicit; here it is a manual gate per clone. The
regression is intentional on Codex's side (supply-chain caution — repo
hooks are third-party code from the CLI's point of view) and mirrors the
same caution this harness itself recommends for `AGENTS.override.md` files
in unfamiliar repos.

## Verification

After trusting, confirm hooks actually fire: from the repo root, attempt a
bare `git checkout -b test-branch` inside a harness session once CX-50 has
landed — the main-branch guard must block it. If it does not, hooks are not
trusted (or not registered) and NO pipeline work should proceed: a gate that
cannot evaluate fails closed (Iron Law 8).

## Registered hooks (Phase 5 — CX-50, CX-51, CX-53)

`.codex/hooks/hooks.json` registers these command hooks. Review each script
before trusting it:

| Event | Script | Blocks? | Purpose |
|-------|--------|---------|---------|
| PreToolUse (Bash) | `main-branch-guard.sh` | yes (exit 2) | CX-50 — refuses HEAD-mutating git at REPO_ROOT without a worktree-delegation prefix; blocks destructive verbs without a live confirmation token |
| PostToolUse (Write/Edit) | `code-shape-check.sh` | yes (exit 2) | CX-51 — whole-file line-cap on source files |
| PostToolUse (Write/Edit) | `function-body-check.sh` | yes (exit 2) | CX-51 — per-language function-body cap (Ruby 5 / TS 12 / Py-Go 8) on new/changed code |
| PostToolUse (Write/Edit) | `comment-smell-check.sh` | yes (exit 2) | CX-51 — blocks new WHAT comments; allows WHY:/SAFETY:/doc-comments |
| SessionStart | `worktree-reaper.sh` | no (exit 0) | CX-53 — reaps only provably-safe merged worktrees under `.claude/worktrees/` |
| SessionStart | `learning-gc.sh` | no (exit 0) | CX-53 — delegates GC to the shared-root learning engine when present, else no-ops |
| SessionStart | `codebase-map-rebuild.sh` | no (exit 0) | CX-53 — DEFERRED STUB (the tree-sitter generator is not ported) |

Vendored helpers under `.codex/hooks/_lib/` (also reviewed by trusting the
scripts that source them): `harness-paths.sh`, `main-branch-detect.sh`,
`main-branch-detect-regex.sh`, `destructive-verb-detect.sh`,
`destructive-verbs.txt`, `check-bypass-gate.sh`.

## Schema assumptions (conservative, flagged for CX-90 probe)

The exact Codex `hooks.json` schema was not fully pinned in the fetched doc
set, so these hooks were registered against the conservative documented form
and the following assumptions — confirm them against your Codex version before
relying on the enforcement layer:

1. **Payload shape.** Each script reads a JSON payload on stdin with
   `.tool_name` and `.tool_input.command` / `.tool_input.file_path` (the
   Claude-harness field names). If your Codex build names these fields
   differently, the single change point is the `jq` extraction at the top of
   each script — the block logic below it is field-name-agnostic.
2. **Matcher key.** Groups use `"matcher": "Bash"` / `"Write|Edit"`. If Codex
   uses a different match key, the hooks still fire (they self-filter on
   `.tool_name` internally) — the matcher is an optimisation, not the gate.
3. **Working directory.** The `args` resolve the script via
   `${CODEX_PROJECT_ROOT:-$PWD}/.codex/hooks/...`. If Codex invokes hooks with
   a CWD other than the project root and does not export `CODEX_PROJECT_ROOT`,
   set that variable or replace the prefix with an absolute path.
4. **Exit-2 on PostToolUse.** The shape hooks signal a violation with exit 2
   on the PostToolUse event, mirroring the Claude harness. Exit-2 blocking is
   verified for `command` hooks (PLAN.md §3); the PostToolUse feedback surface
   is assumed equivalent.

## Reversibility escapes

The SessionStart maintenance hooks honour both the cross-harness
`CLAUDE_DISABLE_*` and the Codex-native `CODEX_HARNESS_DISABLE_*` bypass vars:
`*_WORKTREE_REAPER`, `*_LEARNING_GC`. Set either to `1` to short-circuit.
