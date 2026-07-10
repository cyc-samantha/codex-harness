# Per-Role Subagent Configs (`.codex/agents/*.toml`)

One TOML file per agent role (~20 total), mirroring the source harness's
`agents/*.md`. Populated by Phase 2 (CX-20).

Required fields per role: `name`, `description`, `developer_instructions`
(the ported role-definition body — TDD protocol, decision ladder,
self-review checklist — lives verbatim in `developer_instructions`).
Optional: `model`, `model_reasoning_effort`, `sandbox_mode`, and
`skills.config` to pre-enable/disable skills per role.

Known gap (PLAN §2): Codex has no per-role `tools:` allowlist enforcement.
`skills.config` loosely scopes the *skill* surface only; raw tool access
(Bash/Write/Edit) is ungated pending the CX-90 probe. Until then the
allowlist is an AGENTS.md-level advisory.
