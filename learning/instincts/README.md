# Curated Instinct Seed (`learning/instincts/`)

Curated instinct files shipped with the harness — the seed content the
`harness-learn` skill (CX-32) grows from. Runtime-learned instincts land
under `$CODEX_HOME/harness-data/learning/{project-hash}/instincts/`, never
here. Schema is unchanged from the source harness.

Injection path: `scripts/lib/instinct-inject.py` (CX-33) resolves
role/confidence/dedup/sort and concatenates the rendered `## Learned
Patterns` block into the assembled prompt BEFORE each `codex exec` call —
same prompt-assembly position as the Claude harness's Agent Spawn protocol.
