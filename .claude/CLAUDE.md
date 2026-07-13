# codex-harness

Port of the Claude Code harness (`~/.claude`: skills, agent team,
enforcement hooks, memory/recall, continuous learning, internal eval) onto
OpenAI Codex CLI. The authoritative plan is `PLAN.md` (capability mapping,
architecture, CX-numbered work breakdown); the ported playbook itself is
`AGENTS.md` (stands alone: 13 Iron Laws, code shape rules, phase order,
worktree/commit protocol).

## Commands

- **Test**: `bats tests/shell/` — the enforcement-hook suite (Phase 5,
  CX-50..54). Requires `bats` and `jq` on PATH. CI runs the same command via
  `.github/workflows/harness-gate.yml` on PRs touching `.codex/hooks/**`,
  `.codex/rules/**`, `.agents/skills/**`, or `tests/shell/**`.
- **Lint/Build/Dev server**: n/a — this is a bash/Python/TOML/markdown
  harness repo, not an application

## Architecture

Layout per `PLAN.md` §3 (as revised by the Phase 7 contractor pivot and the
Phase 8 cull, CX-70..87):

- `AGENTS.md` — merged CLAUDE.md + rules/core.md, Codex-native autoload
- `.agents/skills/` — ported skill catalog (~24 contractor-core dirs)
- `.codex/` — `config.toml`, `hooks/`, `rules/` (no `agents/*.toml` role
  team — Codex is a single-thread contractor, not an orchestrator)
- `scripts/` — `install-skills.sh` only (no dispatch layer)
- `pipeline-state/` — portable per-task state contract, including the
  `HANDOFF-CONTRACT.md` baton protocol (runtime content gitignored)

## Service Context

- **Role**: standalone (developer-tooling harness, single deploy unit)
- **Upstream**: OpenAI Codex CLI (consumer), source harness at `~/.claude`
  (port origin)
- **Downstream**: none
- **Contracts**: `pipeline-state/` markdown contract — including
  `HANDOFF-CONTRACT.md` — kept byte-identical to the Claude harness for
  cross-harness portability; runtime state (memory, eval, learning) lives
  in the shared `${HARNESS_DATA:-$HOME/.claude}` root, not a local copy
- **Deploy Dependencies**: none

## Conventions

- LF line endings enforced via `.gitattributes` (`* text=auto eol=lf`) —
  a CRLF-touched `AGENTS.md` once produced an 872-line phantom diff
- All implementation work happens in worktrees under `.claude/worktrees/`
  (gitignored); repo-root HEAD stays on `main` (Iron Law 4)
- Task IDs follow the PLAN's `CX-NN` scheme; reference them in commits
- Runtime state never committed — only code and curated seed content

## Gotchas

- `.codex/config.toml` ships with `[mcp_servers.memory]` commented out;
  uncommenting it points at the shared `${HARNESS_DATA:-$HOME/.claude}/
  mcp_memory/server.py` (the live Claude-side server — there is no local
  `memory/` port). Uncommenting before that path is reachable fails every
  `codex exec` (by design — `required = true` is fail-closed)
- Fresh clones need the one-time hook trust step: `.codex/hooks/TRUST.md`
- Codex `.rules` are experimental — defense-in-depth only, never the sole
  enforcement layer
