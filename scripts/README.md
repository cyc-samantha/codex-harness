# Orchestration Layer (`scripts/`)

`codex-harness` (bash entrypoint, CX-21) replaces "the orchestrator": it
never writes source code (Iron Law 3 substitute — the wrapper stays small
and reviewed). It only creates/removes worktrees, assembles prompts (skill
body + agent role + instincts + session memory + scratchpad + prior phase's
`## Next Phase Input`), invokes `codex exec --profile <role> --cd
<worktree> --sandbox workspace-write --output-schema <verdict-schema>`,
parses the verdict, writes `pipeline-state/{task-id}/{phase}.md`, and
advances phases in the same order as the Claude harness.

## Layout (populated in Phases 2-3)

| Path | Task | Purpose |
|---|---|---|
| `codex-harness` | CX-21 | Dispatcher: `pipeline start\|resume\|status` |
| `lib/dispatch-agent.sh` | CX-22 | worktree-create → `codex exec` → verdict → merge |
| `lib/verdict-parse.py` | CX-23 | `--output-schema` JSON → verdict enum |
| `lib/dispatch-bestofn.sh` | CX-24 | N parallel rollouts (`&` + `wait`) |
| `lib/phase-order.sh` | CX-25 | Phase state machine |
| `lib/dispatch-fix.sh` | CX-26 | In-cycle fix-engineer rework loop |
| `lib/instinct-inject.py` | CX-33 | Instinct/memory prompt splice (pre-`codex exec`) |
| `lib/session-memory.sh` | CX-34 | Session-memory sub-file management |

Every `lib/*.sh` honors `CODEX_HARNESS_DISABLE_*` reversibility escapes
(CX-27).
