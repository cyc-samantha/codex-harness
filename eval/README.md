# Internal Eval (`eval/`)

Baseline/suite/regression-diff machinery ported in Phase 4 (CX-40..CX-42).

- `baselines/` — `{date}-{model}.md` reports, byte-for-byte the same format
  as the Claude harness's so reports are directly diffable across harnesses
- `cases/` — captured real-world cases; each case's `run.sh` invokes
  `codex exec` (CX-41)
- `suites/` — suite definitions grouping cases

Cross-harness bonus (PLAN.md §3): one `cases/` corpus can score BOTH
harnesses — the origin harness has no cross-agent-vendor eval today.
