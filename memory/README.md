# Memory Subsystem (`memory/`)

Ports of the source harness's `learning/`, `db/`, and `session-memory/`
machinery — pure Python stdlib with zero dependency on which coding agent
invokes them, so they port byte-for-byte (PLAN.md §3, FULL fidelity).
Populated by Phase 3 (CX-30, CX-34).

| Subdir | Contents |
|---|---|
| `reindex-memory/` | Rebuild `memory.sqlite` from `observations.jsonl` + scratchpad findings |
| `recall/` | 3-tier progressive-disclosure query API (search / timeline / hydrate) |
| `capture/` | Privacy sanitizer applied before any memory INSERT |
| `mcp_memory/` | stdio JSON-RPC server, registered in `config.toml` at CX-31 with `required = true` (fail-closed, Iron Law 8) |

Runtime data (`memory.sqlite`, per-session dirs) lives under
`$CODEX_HOME/harness-data/`, never in this repo — only code and curated
seed content is committed here.
