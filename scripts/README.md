# Scripts (`scripts/`)

Codex is a single-thread contractor, not an orchestrator (see PLAN.md §5
Phase 7 pivot) — there is no dispatch layer here. The only script is the
skill-catalog installer.

| Path | Purpose |
|---|---|
| `install-skills.sh` | Symlinks (not copies) this repo's `.agents/skills/harness-*` catalog into a target repo's Codex skill-discovery scope. Idempotent; see the script's header comment for usage. |
