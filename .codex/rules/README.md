# Rules (`.codex/rules/*.rules`)

Destructive-verb `prefix_rule(pattern=[...], decision="forbidden")` entries,
ported from the source harness's Non-LLM Gate (Iron Law 4 companion).
Populated by Phase 5 (CX-52) as `harness-destructive.rules`.

CAUTION: Codex `.rules` are explicitly experimental ("may change" per
OpenAI's own docs). Treat rules here as defense-in-depth alongside the
`main-branch-guard.sh` hook port (CX-50) — never as the sole enforcement
layer. See PLAN.md §7 Risks.
