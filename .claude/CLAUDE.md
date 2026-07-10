# codex-harness

Port of the Claude Code harness (`~/.claude`: skills, agent team,
enforcement hooks, memory/recall, continuous learning, internal eval) onto
OpenAI Codex CLI. The authoritative plan is `PLAN.md` (capability mapping,
architecture, CX-numbered work breakdown); the ported playbook itself is
`AGENTS.md` (stands alone: 13 Iron Laws, code shape rules, phase order,
worktree/commit protocol).

## Commands

- **Test**: none yet — arrives with `scripts/lib/verdict-parse.py` unit
  tests (CX-23) and hook tests (Phase 5)
- **Lint/Build/Dev server**: n/a — this is a bash/Python/TOML/markdown
  harness repo, not an application

## Architecture

Layout per `PLAN.md` §3:

- `AGENTS.md` — merged CLAUDE.md + rules/core.md, Codex-native autoload
- `.agents/skills/` — ported skill catalog (~62 dirs, Phase 1)
- `.codex/` — `config.toml`, `agents/*.toml` (~20 roles), `hooks/`, `rules/`
- `scripts/` — `codex-harness` orchestration entrypoint + `lib/` (Phase 2)
- `memory/`, `learning/instincts/`, `eval/` — Python-stdlib subsystems
  (Phases 3-4)
- `pipeline-state/` — portable per-task state contract (runtime content
  gitignored)

## Service Context

- **Role**: standalone (developer-tooling harness, single deploy unit)
- **Upstream**: OpenAI Codex CLI (consumer), source harness at `~/.claude`
  (port origin)
- **Downstream**: none
- **Contracts**: `pipeline-state/` markdown contract, `eval/baselines/`
  report format — both kept byte-identical to the Claude harness for
  cross-harness portability
- **Deploy Dependencies**: none

## Conventions

- LF line endings enforced via `.gitattributes` (`* text=auto eol=lf`) —
  a CRLF-touched `AGENTS.md` once produced an 872-line phantom diff
- All implementation work happens in worktrees under `.claude/worktrees/`
  (gitignored); repo-root HEAD stays on `main` (Iron Law 4)
- Task IDs follow the PLAN's `CX-NN` scheme; reference them in commits
- Runtime state never committed — only code and curated seed content

## Gotchas

- `.codex/config.toml` ships with `[mcp_servers.memory]` commented out
  until CX-31; uncommenting before `memory/mcp_memory/` exists fails every
  `codex exec` (by design — `required = true` is fail-closed)
- Fresh clones need the one-time hook trust step: `.codex/hooks/TRUST.md`
- Codex `.rules` are experimental — defense-in-depth only, never the sole
  enforcement layer
