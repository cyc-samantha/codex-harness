# Ported Skill Catalog (`.agents/skills/`)

One directory per harness skill, in Codex CLI's native Skills format
(`<name>/SKILL.md` with `name` + `description` frontmatter, progressive
disclosure, optional `scripts/`, `references/`, `assets/`).

Populated by Phase 1 (CX-10 through CX-13) from the source harness at
`~/.claude/skills/`. Port decisions per skill (PROMPT / SCRIPT / MERGED /
DROPPED) live in `PLAN.md` §6 Skill Port Catalog. Every `PROMPT`-decision
skill (58 dirs) plus `internal-eval`'s orchestration-shell `SKILL.md` (its
`run`/`score`/`capture`/`validate` sub-skills are `SCRIPT`, Phase 4 scope,
and are not ported here) is present below, plus `harness-resume-handoff`
(Phase 7 contractor-handoff kit, CX-72, no Claude-harness source
counterpart — new to codex-harness) — **60 skills total**.

Every ported directory is prefixed `harness-<name>` (Codex has no per-repo
namespace, so the prefix avoids collision with a target repo's own skills
once installed via `scripts/install-skills.sh`).

Constraint honored when porting (CX-10): Codex caps the initial skill list
at 2% of the model context window (or 8,000 characters when unknown), so
skill `description:` fields were audited and trimmed to front-load trigger
words. **Aggregate `description:` character count across all 60 ported
skills: 8,516** (measured post-trim; each individual description is under
300 characters).

Skipped from this port (see `PLAN.md` §6 for full rationale):

- `README.md`, `_deferred` — not a skill directory.
- `_template`, `capture`, `cost-report`, `embedder`, `mcp_memory`, `recall`,
  `reindex-memory` — `SCRIPT`, ported as orchestration-script/Python
  subsystems in later phases (CX-30, Phase 4/5), not as Codex Skills.
- `best-of-n`, `cache-flip-gate`, `debug-trace`, `pdr-rtv`,
  `plan-cache-rollout-gate`, `swe-pruner-rollout-gate` — `MERGED` into
  orchestration-script logic (Phase 2/5).
- `design-qc`, `vlm-critic` — `DROPPED` (VLM/Computer-tool parity
  unverified on Codex).
- `spec_grounding` — `DROPPED` (legacy duplicate of `spec-grounding`).
- `internal-eval/run`, `internal-eval/score`, `internal-eval/capture`,
  `internal-eval/validate`, `internal-eval/tests` — `SCRIPT` sub-skills of
  `internal-eval`, Phase 4 (CX-40/41/42) scope.

## Catalog

| Skill dir | Decision | Description |
|---|---|---|
| `harness-accessibility-check` | PROMPT | Run axe-core against changed routes and gate on WCAG 2.1 AA violations; invoked by the pipeline after frontend Build and by design-qc in-process during Final Gate. |
| `harness-api-scaffold` | PROMPT | Use when user wants to Generate API endpoints from spec: route definitions, controllers, request/response validation, error handling, pagination, rate limiting. |
| `harness-batch-pipeline` | PROMPT | Lightweight pipeline for pre-planned batch work (production readiness waves, bulk fixes). Preserves critical infrastructure (state, scratchpad, observations) while skipping redundant phases. |
| `harness-bug-fix` | PROMPT | Root cause analysis workflow with incremental TDD for bug fixes. Covers reproduce, analyze, regression test, fix, verify, and prevent. |
| `harness-build-implementation` | PROMPT | Structured Build-phase TDD implementation: RED-GREEN-REFACTOR per slice, mutation kill loop. Use when implementing acceptance criteria after a plan is approved. |
| `harness-cache-audit` | PROMPT | Aggregates per-session cache.jsonl into a project-wide prompt-cache read-ratio report. Use to check caching effectiveness or as a periodic health check. |
| `harness-changelog` | PROMPT | Use to ship a PR with a human-readable narrative and changelog entry: derives a 'what changed and why' PR body plus a Keep-a-Changelog entry from the diff and ACs. |
| `harness-code-review` | PROMPT | Use when user wants to Review phase skill: spawn code-reviewer agent to audit code for SOLID/DRY violations, security issues, test quality, performance, and complexity. |
| `harness-continuous-planning` | PROMPT | Long-lived planning agent that watches pipeline scratchpad findings during multi-slice Build and refines the active plan when findings contradict it. Spawned when slice_count >= 2. |
| `harness-creative-direction` | PROMPT | Pre-build design thinking phase producing a distinctive design brief: font pairing, color palette, layout philosophy, interaction paradigm, visual personality. |
| `harness-db-migration` | PROMPT | Use when user wants to Structured database migration workflow. |
| `harness-debt-ledger` | PROMPT | Advisory grep-collector that harvests every `DEBT:` deliberate-simplification marker across the tree, renders a ledger grouped by file, and flags `no-trigger` entries. |
| `harness-debug` | PROMPT | Persistent debug state management for complex, multi-session bugs. Maintains structured debug state files under HARNESS_DATA that survive context compaction. |
| `harness-deploy` | PROMPT | Use when user wants to Continuous deployment skill: environment-aware deploy with pre-flight checks, staging verification, production rollout, and rollback. |
| `harness-deployment-verification` | PROMPT | Use when user wants to Post-deploy verification: health checks, smoke tests against live URL, error rate monitoring, automatic rollback trigger. |
| `harness-design-system-init` | PROMPT | Use when user wants to Generate design tokens, primitive components, and dark mode for a project. |
| `harness-epic-breakdown` | PROMPT | Decompose an epic into estimated stories with acceptance criteria. Orchestrates architect for design, estimation for sizing, and outputs structured stories. |
| `harness-estimation` | PROMPT | Use when sizing stories with the Complexity Budget. Scores 5 dimensions (scope, ambiguity, context pressure, novelty, coordination) 1-3 each. |
| `harness-eval-model-effectiveness` | PROMPT | Analyzes accumulated pipeline observations and cost metrics to recommend per-role model downgrades/upgrades when outcomes are statistically indistinguishable. |
| `harness-forensics` | PROMPT | Post-incident investigation of pipeline runs: reconstructs timelines from trajectory JSONL, analyzes anomalies (gaps, retries, long phases). |
| `harness-greenfield-scaffold` | PROMPT | Full greenfield project bootstrap: product discovery, tech stack decision, UI architecture, framework init, DevX setup, design system, infrastructure, and seed data. |
| `harness-harness-audit` | PROMPT | Use when user wants to Audit the health of the harness config: orphan hooks, missing skills, stale agents, JSON validity, hook executability. |
| `harness-harness-config` | PROMPT | Modify the harness itself: hooks, settings, agent definitions, skill infrastructure. Delegates non-.md changes to an infrastructure-engineer with worktree isolation. |
| `harness-health-scan` | PROMPT | Use when user wants to Scan a codebase for security vulnerabilities, dependency freshness, test coverage gaps, tech debt signals, and dead code. |
| `harness-infra-scaffold` | PROMPT | Use when user wants to Generate production-ready infrastructure config: Dockerfile, docker-compose, CI/CD pipeline, health endpoints, env management. |
| `harness-intake` | PROMPT | Entry point for all user requests: fingerprints and tier-routes (T0-T6) work before pipeline dispatch. Use at the very start of any new task or feature request. |
| `harness-internal-eval` | PROMPT | Eval phase: suite execution, baseline capture, and regression diff across captured real-world harness cases. (Orchestration shell only — `run`/`score`/`capture`/`validate` sub-skills are `SCRIPT`, Phase 4.) |
| `harness-learn` | PROMPT | Use when user wants to Analyze recent session observations and extract instincts (learned patterns). |
| `harness-load-test` | PROMPT | Use when user wants to Performance verification phase: run load tests against staging, establish baselines, verify SLAs, detect regressions. |
| `harness-module-extraction` | PROMPT | Use when user wants to extract a bounded context into an in-process module with an explicit public port (same repo, no new process or deploy unit). |
| `harness-mutation-score-report` | PROMPT | Aggregates per-session mutation-score signals into a soak-progress report toward the >=10 sessions / >=70% median promotion bar. |
| `harness-observability-setup` | PROMPT | Use when setting up production observability: structured logging, metrics, tracing, alerting for a service. |
| `harness-patch-critique` | PROMPT | Use for Final-Gate evaluation of a candidate patch by test results + diff (not SOLID/DRY). |
| `harness-pipeline` | PROMPT | Autonomous pipeline orchestration: classifies work, determines phases, tracks state, invokes skills in sequence, manages review loops and error recovery. |
| `harness-pipeline-resume` | PROMPT | Use when user wants to Resume an in-progress pipeline from pipeline-state/ files. |
| `harness-plan-cache-lookup` | PROMPT | Plan-phase Stage 0 cache gate: checks the plan-template cache by (task_class, repo_hash, tier) key before recon + architect run. |
| `harness-plan-self-validation` | PROMPT | Lightweight Plan Validation for non-critical, low-budget pipelines: architect re-reads its own plan against a holes-finding rubric, returns PLAN_APPROVED or PLAN_HOLES. |
| `harness-polish` | PROMPT | Use when user wants to Lightweight mechanical cleanup pass between Build and Review. |
| `harness-pr-creation` | PROMPT | Use when user wants to ship a feature: GitHub pull request workflow with validation, feature branch management, and automated PR creation. |
| `harness-product-acceptance` | PROMPT | Use when user wants to Accept phase skill: spawn product-reviewer to validate acceptance criteria are met, assess UX quality, and verify business value delivery. |
| `harness-project-setup` | PROMPT | Scaffold a project-level AGENTS.md by detecting tech stack, commands, architecture, and conventions. |
| `harness-property-based-test` | PROMPT | Build-phase utility: spawns pbt-engineer to author Tier 1.5 property-based tests for changed-line public functions with typed signatures (60s/function time-box). |
| `harness-qa-test-strategy` | PROMPT | Use when user wants to Test phase skill: spawn qa-engineer to map acceptance criteria to tests, identify coverage gaps, and write integration/E2E tests. |
| `harness-react-native-patterns` | PROMPT | Use when user wants to Expo Router v4 patterns, NativeWind, Gluestack UI v3, TanStack Query + Zustand, platform handling, Maestro E2E. |
| `harness-refactor` | PROMPT | Use when user wants to Safe refactoring workflow: identify smell, write characterization tests, refactor in small steps, verify green after each. |
| `harness-resume-handoff` | PROMPT | Resume work handed off by the Claude harness: reads ACTIVE_HARNESS baton + HANDOFF.md, reconciles against git ground truth, continues the task vertically, and wraps by writing a return HANDOFF.md with baton: claude. |
| `harness-sandbox-verify` | PROMPT | Build-phase gate: runs the test suite in a remote E2B sandbox and compares pass sets against the worktree. |
| `harness-security-alert-fix` | PROMPT | Use to investigate and fix open GitHub security alerts (CodeQL + secret-scanning). |
| `harness-security-review` | PROMPT | Security Review phase: spawns security-engineer for OWASP Top 10 audit, dependency scanning, secrets detection, auth/authz review. Runs after Build and gates Final Gate. |
| `harness-skill-builder` | PROMPT | Create new Skills with proper YAML frontmatter, progressive disclosure structure, and directory organization. |
| `harness-skill-security-lint` | PROMPT | Scan changed SKILL.md and skill _lib files for prompt-injection patterns, hardcoded secrets, and over-broad tool grants. |
| `harness-smell-scan` | PROMPT | Advisory Fowler-catalog smell sweep on changed files. Use to check for Feature Envy, Data Clumps, Shotgun Surgery, and other architectural smells before review. |
| `harness-spec-blind-validate` | PROMPT | Final-Gate teammate: authors black-box behavioural tests from the AC plan + public API only, never from src/. Catches SWE-Bench-Pro-vs-Verified overfitting. |
| `harness-spec-grounding` | PROMPT | Ground raw acceptance criteria against codebase evidence and recall. Invoked as Step 2c-ter (Stage 0 of Plan Phase) before the architect runs. Emits EARS-tagged ACs with per-AC citations. |
| `harness-story-writing` | PROMPT | Write a single well-formed user story as a value statement plus testable acceptance criteria with failing-test stubs and a Complexity Budget. |
| `harness-tech-spike` | PROMPT | Use when user wants to Time-boxed technical research workflow: question, explore, prototype, findings, recommendation. |
| `harness-tool-synthesis` | PROMPT | Use when standard tools can't do the job and a one-shot scratch tool would help (codebase-specific search, AST analyzer, repo-specific linter). |
| `harness-verify` | PROMPT | Use when user wants to Structured verification workflow: contract tests, smoke tests, mutation testing. |
| `harness-web-frontend-patterns` | PROMPT | Web frontend tech-stack pattern reference (React/Next.js/Vite/Remix). Use for framework-specific build/debug/verify guidance. |
| `harness-workstream` | PROMPT | Manage isolated workstreams for parallel feature development. |

## Installation

`scripts/install-skills.sh [target-dir]` symlinks every `harness-*` skill
directory from this repo's `.agents/skills/` into
`<target-dir>/.agents/skills/`. Defaults to `.` (this repo's own root scope)
when no argument is given. Idempotent — safe to re-run; refreshes stale
symlinks and reports (without clobbering) any pre-existing non-symlink path.
