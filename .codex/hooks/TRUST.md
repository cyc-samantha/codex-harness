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

**Fail-open vs fail-closed, distinguished.** The `hooks.json` launcher itself
is intentionally fail-open on ONE narrow condition: `main-branch-guard.sh`
absent from disk or not executable (`[ -x "$h" ]` false). That is a
*script-availability* check, not a command-evaluability check — it exists so
a partially-broken checkout doesn't brick every tool call. It now prints a
loud `WARNING: ... enforcement is INERT this session` to stderr before
`exit 0` (previously silent — the exact gap this section originally warned
about). This is DIFFERENT from the guard SCRIPT's own behaviour once it does
run: `main-branch-guard.sh` fails CLOSED (`exit 2`) on an unevaluable
payload — empty stdin, non-JSON — per Iron Law 8. In short: missing/non-
executable script → loud fail-open (a deployment defect, now visible);
present-but-can't-parse-input → fail-closed (a security property). If you
ever see the launcher warning, the executable bit regression this file's
"regression pin" bats test (`tests/shell/test_exec_bit.bats`) exists to
catch has likely resurfaced — treat it as a P0 and re-run
`git update-index --chmod=+x .codex/hooks/*.sh` (top-level executed scripts
only; `_lib/*.sh` are sourced, not executed, and stay 100644).

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

**Upstream-drift risk.** `main-branch-detect-regex.sh` was vendored verbatim
from the source Claude harness (`~/.claude/hooks/_lib/`) but has since
DIVERGED: this port adds `_mbd_strip_leading_wrappers` to close a
wrapper-bypass gap (security-review rounds 1-2; code-review round 3) that
the upstream file does not have. Round 2 replaced an attached-flag-only
regex with a token-scan that drops every token up to the first bare
`git`/`gh` — this also closes `env`'s `KEY=VALUE`/`-i` forms and
separate-arg wrapper flags (`nice -n 10`, `stdbuf -o 0`) and mandatory
positional args (`timeout 5`). A future re-sync of this file from the
source harness (manual copy, `cp`, or a sync script) will silently reopen
the bypass unless the stripping step is re-applied. The file carries a
`DIVERGENCE NOTE` comment at its top for exactly this reason — read it
before touching the file.

**Wrapper detection is an enumerated allow-list, not exhaustive coverage.**
`_mbd_strip_leading_wrappers` only strips a fixed, named set of leading
tokens — currently `command`, `env`, `nice`, `nohup`, `time`, `stdbuf`,
`timeout`, `setsid`, `ionice`, `chrt`, `taskset`, `flock`, `sudo`, `doas`
(code-review round 3 added the last seven after live probes confirmed
`setsid git checkout main` and `sudo git checkout main` bypassed the
guard). Any unprivileged exec-passthrough wrapper NOT on this list will
push the git verb off the anchored patterns and bypass detection the same
way. This is defense-in-depth, not a claim of completeness — new wrapper
binaries can appear at any time. Known boundaries in the same class,
carried forward from code-review round 3 and intentionally NOT fixed here
(pre-existing, out of scope, shell-parsing-completeness problems a regex
hook cannot fully solve):

- **Leading-backslash alias escape.** `\git checkout main` is allowed
  because the leading backslash pushes `git` off the anchor; under a
  wrapper, `nice \git checkout main` empties the stripped command entirely.
- **Quote-unaware clause splitter.** `split_clauses` splits on `;`/`&&`/`|`
  without honouring quotes, so `git commit -m "fix; git checkout main"` is
  wrongly BLOCKED (false positive on a mutating verb inside a quoted commit
  message).

`.rules` and human review remain the backstop for whatever this enumerated
list and the regex grammar cannot express — never treat this file as the
sole enforcement layer.

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

`CLAUDE_DESTRUCTIVE_VERBS_FILE` (read by `_lib/destructive-verb-detect.sh`)
overrides the path `is_destructive_command` loads its verb patterns from.
It is a legitimate escape for testing (point it at a fixture file) but is
also a full bypass surface: pointing it at `/dev/null` or any file with no
matching patterns makes `is_destructive_command` never match, so
`main-branch-guard.sh` never asks for the
`CLAUDE_DESTRUCTIVE_CONFIRM`/`CLAUDE_DESTRUCTIVE_CONFIRM_TS` confirmation
token before a destructive verb runs. This was previously undocumented.
Treat any session with `CLAUDE_DESTRUCTIVE_VERBS_FILE` set to a
non-standard path with the same suspicion as one with the confirmation
token pre-set.
