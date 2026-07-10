# Ported Skill Catalog (`.agents/skills/`)

One directory per harness skill, in Codex CLI's native Skills format
(`<name>/SKILL.md` with `name` + `description` frontmatter, progressive
disclosure, optional `scripts/`, `references/`, `assets/`).

Populated by Phase 1 (CX-10 through CX-13) from the source harness at
`~/.claude/skills/`. Port decisions per skill (PROMPT / SCRIPT / MERGED /
DROPPED) live in `PLAN.md` §6 Skill Port Catalog — ~62 of 77 source entries
port here essentially unchanged.

Constraint to honor when porting (CX-10): Codex caps the initial skill list
at 2% of the model context window (or 8,000 chars when unknown), so skill
`description:` fields must stay terse with trigger words front-loaded.
