# codex-harness — Global Playbook

This is the codex-harness global playbook: the merged equivalent of the
Claude harness's `CLAUDE.md` + `rules/core.md`, ported onto Codex CLI's
native `AGENTS.md` autoload chain (global `~/.codex/AGENTS.md` → repo root →
nested `AGENTS.md` files, with `AGENTS.override.md` taking precedence over
whatever it sits alongside — nearer files silently win). This file is
designed to **stand alone**: a fresh Codex session that reads only this file
must be able to state the phase order, all 13 Iron Laws, the code shape
rules, and the worktree/commit protocol without chasing another file. Other
sections below reference `PLAN.md` or not-yet-built pieces, and are marked as
such.

> **Caution — `AGENTS.override.md` precedence.** Codex's discovery chain
> lets a file closer to the working directory silently override this one.
> Before trusting any repo you did not author, check for an
> `AGENTS.override.md` anywhere between the repo root and your working
> directory and read it — a hostile or stale override can quietly disable
> the Iron Laws below for that subtree. This mirrors the same supply-chain
> caution this harness applies to `.codex/hooks/` (see Onboarding, below).

## Onboarding — one-time hook trust step

Codex requires reviewing and trusting non-managed `command`-type hooks
before they run (`/hooks` in the CLI). Every fresh `codex-harness` checkout
needs this **one-time manual trust step** — Claude's hooks are trusted
implicitly by living under `~/.claude/hooks/`, which the user already
controls; Codex has no equivalent implicit trust. Run `/hooks`, review every
entry registered from `.codex/hooks/hooks.json`, and trust them before
starting any pipeline work in this repo. Do not skip this because a hook
"looks routine" — it is the only thing standing between you and an
unreviewed script executing on every tool call.

## Engineering Identity

- Lean agile: thin vertical slices delivering observable user value
- MVP mindset: smallest increment that validates the hypothesis
- Ship-learn-iterate: deploy independently, measure, adapt
- Modular monolith by default: in-process boundaries first; new services
  only when a forcing function is explicitly named (see the source harness's
  `protocols/module-boundaries-protocol.md` FF1-FF5 list — not yet ported
  into this repo; treat as referenced-not-transcribed until it lands)
- Engineering discipline: TDD mandatory, SOLID, DRY, clean architecture
- Zero waste: every output line is a test result or a real error
- Proven correct: tests passing is necessary but not sufficient — verify it
  actually works

## Iron Laws (1-13)

Same bracketed-tag convention as the source harness: `[ASPIRATIONAL]` marks
a law not backed by a blocking enforcement surface; `[ENFORCED]` marks a law
with a shipped, blocking enforcement surface. The **Claude status** column
below is the source harness's own status marker, preserved for reference.
The **Codex status** column is this harness's own status, which is often
weaker than Claude's — Codex has no native "pipeline phase verdict gate"
primitive at all, so several laws downgrade from enforced/log-only to
advisory, script-enforced. This downgrade is an intrinsic architecture gap
(no primitive to lean on), not a maturity gap that closes as Codex hooks
improve — see the summary note at the end of this section.

1. **NO ACCEPTANCE CRITERION SHIPS WITHOUT (a) a failing-then-passing test
   for that AC in the diff and (b) mutation score ≥ 70% on changed lines.**
   Claude status: `[ASPIRATIONAL]`. Codex status: **ADVISORY, script-enforced**
   — `scripts/codex-harness` (Phase 2, CX-21/CX-25) checks for a
   failing-then-passing test pair and a mutation-score report before
   advancing the Build phase's verdict; there is no hook-level block on the
   underlying `codex exec` tool calls themselves. Substitution mechanism:
   orchestration-script gate at phase-advancement time, backstopped by a
   CI mutation-score check (Phase 5, CX-54).

2. **NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.** Stale test
   output from earlier in a session is not evidence — re-run before
   claiming done. Claude status: `[ASPIRATIONAL]` (log-only in the source
   harness). Codex status: **ADVISORY, script-enforced** — the orchestration
   script re-invokes the test/verify step itself rather than trusting an
   agent's self-report before writing a phase-complete verdict. Substitution
   mechanism: orchestration-script re-verification, same posture as the
   source harness's log-only hook, just moved into the script layer since
   Codex has no `PreToolUse` prompt-mutation interception to lean on (see
   PLAN.md §7 Risks).

3. **THE ORCHESTRATOR NEVER WRITES SOURCE CODE.** Claude status:
   `[ENFORCED]` (`hooks/_lib/is-protected-path.sh` blocks the orchestrator
   from Edit/Write/shell-pipe into protected locations). Codex status:
   **ADVISORY — partial, code-review-time guarantee** — Codex has no
   "orchestrator process" concept for a hook to gate at runtime, so this law
   becomes "the wrapper script's source (`scripts/codex-harness`,
   `scripts/lib/*.sh`) is small, reviewed, and never itself calls
   Edit/Write against protected paths" rather than a hook-blocked
   invariant. Substitution mechanism: code review of the orchestration
   script itself, not a runtime gate.

4. **REPO_ROOT HEAD STAYS ON `main` FOR THE ENTIRE DURATION OF EVERY
   PIPELINE RUN.** All HEAD-mutating git commands run via worktree
   delegation. Claude status: `[ENFORCED]` (`hooks/main-branch-guard.sh`,
   `PreToolUse`, blocks bare `git checkout`/`switch`/`reset --hard`/`merge`/
   `rebase`/`gh pr create`). Codex status: **ENFORCED** — this is the
   strongest native-hook parity point in the whole port, because Codex's
   `PreToolUse` `command`-type hooks genuinely block (`exit`-code semantics
   confirmed), same as Claude's. Substitution mechanism: `main-branch-guard.sh`
   ported 1:1 as a `.codex/hooks/hooks.json` `PreToolUse` entry (Phase 5,
   CX-50), plus `.codex/rules/harness-destructive.rules` `prefix_rule`
   defense-in-depth (CX-52, marked experimental by OpenAI — never the sole
   layer).

5. **NO PHASE SKIPPED. NO GATE BYPASSED. NO SKILL OMITTED.** Every pipeline
   phase runs the corresponding skill; verdicts gate advancement. Claude
   status: `[ASPIRATIONAL]`. Codex status: **ADVISORY** — pure
   orchestration-script sequencing (`scripts/lib/phase-order.sh`, CX-25)
   drives the fixed phase order below and refuses to advance without a
   verdict; there is no native Codex primitive equivalent to a phase gate
   at all. Substitution mechanism: `phase-order.sh` state machine.

6. **FINDINGS SURFACED DURING REVIEW ARE FIXED IN THIS PIPELINE.** Never
   filed as follow-ups, never surfaced as questions to the user, no
   known-incomplete ships except when a fix is architecturally large or
   outside the current task's layer. Claude status: `[ASPIRATIONAL]`. Codex
   status: **ADVISORY** — orchestration-script re-dispatch on
   non-passing verdict (`scripts/lib/dispatch-fix.sh`, CX-26) re-invokes the
   fix-engineer role in-cycle rather than closing the loop and moving on.
   Substitution mechanism: `dispatch-fix.sh` rework loop.

7. **EVERY PIPELINE PRODUCES AN OBSERVATION.** No exceptions — successes
   and failures both; the continuous learning loop depends on data volume.
   Claude status: `[ASPIRATIONAL]`. Codex status: **ADVISORY,
   script-enforced** — the orchestration script's Reflect-phase step writes
   an observation into `observations.jsonl` unconditionally before it will
   mark a pipeline run complete. Substitution mechanism: Reflect-phase step
   in `scripts/codex-harness`, feeding the ported `learn` skill (Phase 3,
   CX-32).

8. **A SECURITY OR CORRECTNESS GATE THAT CANNOT EVALUATE ITS CONDITION
   FAILS CLOSED.** A gate is any check whose verdict admits or stops work —
   halt or refuse on an unevaluable input (empty input, missing file,
   unbound variable, tool error, absent dependency); never silently allow.
   Claude status: `[ASPIRATIONAL]`. Codex status: **PARTIAL — hook-enforced
   where a native `command` hook exists, script-enforced everywhere else** —
   `main-branch-guard.sh` and the code-shape hooks (both native `PreToolUse`/
   `PostToolUse` `command` hooks, Phase 5) fail closed at the tool-call
   level; verdict-level gates with no native hook backing (mutation score,
   observation capture) fail closed only insofar as the orchestration script
   is written to halt on an unevaluable condition rather than proceed.
   Substitution mechanism: split — native hook fail-closed for tool-call
   gates, orchestration-script fail-closed discipline for verdict gates.

9. (DS) **NO MODEL OR ANALYSIS CONCLUSION SHIPS WITHOUT A PRE-REGISTERED
   EXPERIMENT CARD AND A HOLDOUT EVALUATION AGAINST A BASELINE.** Amendments
   to the card after results are seen are logged verdicts
   (`EXPERIMENT_AMENDED`), never silent edits. Claude status:
   `[ASPIRATIONAL]`. Codex status: **ADVISORY, script-enforced** — same
   class as Laws 1/5/6/7: the orchestration script checks for an experiment
   card and holdout-eval artifact before advancing a DS pipeline's verdict.
   Future enforcement surface (not yet ported): a `harness-experiment`
   skill port + card schema, mirroring the source `skills/experiment/` and
   `protocols/experiment-protocol.md`.

10. (DS) **A NEGATIVE OR NULL RESULT IS A VALID PIPELINE OUTCOME.** No agent
    may re-run, re-slice, or re-metric an experiment to flip its verdict;
    additional runs require an `EXPERIMENT_AMENDED` verdict, not a quiet
    re-run. Claude status: `[ASPIRATIONAL]`. Codex status: **ADVISORY** —
    append-only discipline enforced by the orchestration script refusing to
    overwrite a prior experiment-registry entry silently. Future
    enforcement surface (not yet ported): an `evaluation-engineer` role
    port + registry append-only check.

11. (DS) **EVERY DATASET REFERENCE IN A PIPELINE RESOLVES TO AN IMMUTABLE
    VERSION, AND EVERY RUN IS REPRODUCIBLE FROM (code-ref, data-ref,
    env-lock, seed).** Claude status: `[ASPIRATIONAL]`. Codex status:
    **ADVISORY** — same script-enforced-only class; no native Codex
    primitive resolves or locks dataset versions. Future enforcement
    surface (not yet ported): a `data-version` skill/tooling port + a
    `repro-verifier` role port.

12. (DS) **RAW DATA NEVER ENTERS AGENT CONTEXT, TRANSCRIPTS, LOGS, OR
    COMMITS BEYOND CAPPED, PII-MASKED SAMPLES.** Claude status:
    `[ENFORCED at hook-ship time]` (not yet shipped in the source harness
    either, per its own note — being built in parallel by other Wave-1/2
    tasks). Codex status: **ENFORCED at capture time, once ported** — this
    is the one DS law that ports as a native `command`-type hook once the
    ported sanitizer scripts land (mirrors Law 4's native-hook parity),
    because raw-data-in-context is exactly the kind of deterministic,
    exit-2-on-violation check Codex `PreToolUse`/`PostToolUse` hooks handle
    well. Substitution mechanism: ported equivalents of
    `hooks/data-read-guard.sh`, `hooks/data-commit-guard.sh`,
    `hooks/pii-transcript-scan.sh` registered in `.codex/hooks/hooks.json`
    (not yet built in this repo — ships alongside the same source-harness
    parallel task that builds the Claude-side hooks; treat as pending,
    not yet present in `.codex/hooks/`).

13. (DS) **A DATA CONTRACT VIOLATION HALTS THE PIPELINE.** Silent coercion,
    silent null-dropping, and silent row-filtering are treated as
    correctness bugs, not data cleaning. Claude status: `[ASPIRATIONAL]`.
    Codex status: **ADVISORY** — same script-enforced-only class; the
    orchestration script halts phase advancement on a
    `CONTRACT_VIOLATION` verdict from the (not yet ported) `data-contract`
    skill, naming the offending column and expectation, same as the source
    harness's design.

**Summary of what strengthens vs weakens under Codex.** Law 4 (main-branch
invariant) and (once its hooks ship) Law 12 (raw-data guard) are the
strongest native-hook parity points, because both are deterministic,
exit-2-on-violation checks that Codex's `PreToolUse`/`PostToolUse`
`command` hooks genuinely block on, same as Claude's. Laws 1, 2, 5, 6, 7, 9,
10, 11, 13 downgrade to advisory/script-enforced-only because Codex has no
pipeline-phase or verdict-gate primitive at all — this is an intrinsic
architecture gap, not a hook-maturity gap, and will not close as Codex
hooks mature further; it needs the orchestration script
(`scripts/codex-harness` + `scripts/lib/*.sh`) to keep doing this work
indefinitely. Law 3 downgrades because Codex has no "orchestrator process"
concept to gate at runtime — the invariant becomes a code-review-time
guarantee on the wrapper script's own source, not a runtime one. (Source:
`rules/core.md` § Iron Laws 1-8 and `protocols/data-science-invariants.md`
§ DS Iron Laws 9-13 in the Claude harness at
`/home/samanthachen/git/.claude`, transcribed 2026-07-10; Codex
enforcement-status derivation cross-checked against PLAN.md §1 Executive
Summary "What needs re-architecture", §3 Key design moves, and §4's summary
paragraph, since PLAN.md's own §4 table cells were truncated mid-sentence in
the source file — this file's per-law text above is the full, untruncated
restatement.)

## Code Shape Rules

Every code-touching agent enforces continuously.

- **Naming is the primary cohesion gate:** can't name a unit without "and"
  → split; can't give an extract an honest name → do NOT extract.
- **Per-language hard block on new/changed code:** Ruby methods > 5 lines
  blocked (exit 2); TypeScript/JS functions > 12 lines blocked; Python/Go
  fallback cap retained. Legacy code is advisory only.
- **One thing per function.** If you cannot name it without a conjunction
  ("X and Y"), split.
- **Cyclomatic complexity ≤ 5.** Nesting ≤ 2 — guard clauses or extraction,
  not deeper if/else.
- **DRY on 2nd occurrence.** Extract immediately when logic recurs.
- **≤ 4 params** per function. More signals a missing abstraction.
- **Single public entry point** per class (`.call`/`.run`/`.execute`).
- **Entanglement escape valve:** if understanding unit A requires reading
  unit B, bring them together — this is HOW to fix a flagged function, not
  a bypass.
- **Comments carry WHY only.** New/changed WHAT-comments in source are
  blocked (exit 2) by hook; doc-comments, license headers, and
  `# WHY:`/`# SAFETY:` prefixes are always allowed.
- **Don't complect** (Hickey): one concern per unit; complected code defeats
  reasoning and breaks reliability.
- **Classes/files:** one responsibility, no hard size number — size is a
  smell that triggers the naming check. Safety-net cap:
  `CODEX_HARNESS_FILE_LINE_LIMIT` (default 300). Per-glob overrides via a
  `shape-overrides.json` still apply, same mechanism as the source harness's
  `.claude/shape-overrides.json`, retargeted to this repo's config surface.

Full standards (naming, SOLID, error handling, dependency resolution,
security baseline, test mix) are not yet ported into this repo verbatim;
until they are, treat the source harness's `protocols/engineering-invariants.md`
as authoritative and this section's list as the binding subset.

## Worktree + Commit Protocol

- **Write-capable roles** (software-engineer, frontend-engineer,
  qa-engineer, database-engineer, infrastructure-engineer): get a git
  worktree created by `scripts/lib/dispatch-agent.sh` — `git worktree add`
  runs before each `codex exec --profile <role>` invocation for that role.
  This is MANDATORY; Codex has no native per-agent worktree field, so the
  orchestration script does it explicitly (Codex's automatic "Worktree" UI
  feature is scoped to the ChatGPT desktop app only, not `codex exec`).
- **Read-only roles** (code-reviewer, security-engineer, product-reviewer,
  architect): get no worktree — they run against the existing checkout.
- **Every agent commits before completing** — uncommitted work cannot be
  merged. WIP commits use a `WIP:` prefix.
- **No `git add -A` / `git add .`** — stage specific files to avoid
  sensitive-file leakage.
- **REPO_ROOT HEAD stays on `main` for the entire duration of every
  pipeline run.** All HEAD-mutating git commands run via worktree
  delegation (`git -C "$WORKTREE" …` or `(cd "$WORKTREE" && …)`). Bare
  `git checkout`/`switch`/`reset --hard`/`merge`/`rebase`/`gh pr create` are
  blocked by the ported `main-branch-guard.sh` native hook (see Iron
  Law 4, above).

## Pipeline Phase Order

`Plan → Plan Validation → Build (incl. code-review as final step) →
Security Review → Final Gate (Verify + Test + Accept + Patch Critique) →
Ship → Deploy → Reflect`. No phase is skipped. Every phase has a
corresponding skill. Code-review is not its own phase — it runs as the
final step of Build (the value-add is "a second model with different
priors reviewing the diff", not a separate phase boundary). Security review
remains a separate phase (orthogonal concern). Reflect always runs (per
Iron Law 7, above — every pipeline produces an observation).

Build has three dispatch variants — standard, Best-of-N, and PDR-RTV —
selected by the ported `harness-intake` skill's flags, with precedence
`pdr_rtv > bestofn > standard`.

Because Codex has no native "pipeline phase verdict gate" primitive (see
Iron Law 5, above), phase advancement here is entirely
**orchestration-script-gated**: `scripts/codex-harness` (the orchestrator
entrypoint) drives `scripts/lib/phase-order.sh` through this exact sequence,
invoking `codex exec --profile <role> --cd <worktree> --sandbox
workspace-write --output-schema <phase-verdict-schema.json>` per phase,
parsing the verdict JSON, and refusing to advance to the next phase without
a passing verdict written to `pipeline-state/{task-id}/{phase}.md`.

## Work-Class Routing (T0-T6)

`harness-intake` (Step 1.5, Fingerprint) classifies every request into
seven tiers. T0-T3 bypass full pipeline dispatch; T4-T6 enter at
progressively heavier dispatch. Dispatch targets below are ported skill
names, invoked by `$skill-name` mention in the assembled prompt (Codex's
own skill-selection logic then loads the matching `.agents/skills/<name>/SKILL.md`).

| Tier | Class | Dispatch target |
|---|---|---|
| **T0** | Question / Spike | Direct answer or `$harness-tech-spike` |
| **T1** | Doc-only | Lightweight worktree invocation (tracked-doc edits) |
| **T2** | Config-only | `$harness-harness-config` |
| **T3** | Mechanical sweep | `$harness-batch-pipeline` |
| **T3H** | Trivial code change | `$harness-pipeline` (trimmed: Build + diff-only code-review + Ship) |
| **T4** | Bug fix | `$harness-pipeline` (lightweight) |
| **T5** | Standard feature | `$harness-pipeline` (standard) |
| **T6** | Critical / cross-cutting | `$harness-pipeline` (heavy: Best-of-N or PDR-RTV) |

## Agent Team

Ported roles, phases, and worktree requirement from the Claude harness's
Agent Team table. `Default Model` is **TBD** for every row, pending a fresh
Codex cost-quality calibration pass — Codex's model lineup (`gpt-5.6`,
`gpt-5.6-terra`, `gpt-5.4`, `gpt-5.3-codex-spark`) and reasoning-effort
levels (`minimal`/`low`/`medium`/`high`/`xhigh`/`max`/`ultra`,
model-dependent) do not map 1:1 onto the source harness's opus/sonnet/haiku
tiering (PLAN.md §7 Risks). Do not naively rename Claude's per-role model
defaults onto this table until that calibration pass runs.

| Agent | Phase | Worktree | Default Model |
|-------|-------|----------|---------------|
| architect | Plan | No | TBD |
| architect-context-recon | Plan (recon) | No | TBD |
| code-reviewer | Build (code-review) | No | TBD |
| database-engineer | Build | Yes | TBD |
| fix-engineer | Build (in-cycle) | Yes | TBD |
| frontend-engineer | Build | Yes | TBD |
| infrastructure-engineer | Build | Yes | TBD |
| patch-critic | Final Gate | No | TBD |
| pbt-engineer | Build | Yes | TBD |
| plan-cache-adapter | Plan | No | TBD |
| planning-agent | Build (advisory) | No | TBD |
| product-reviewer | Accept | No | TBD |
| qa-engineer | Test | Yes | TBD |
| sandbox-verify-engineer | Build | No | TBD |
| security-engineer | Security Review | No | TBD |
| session-memory-updater | Post-phase | No | TBD |
| software-engineer | Build | Yes | TBD |
| spec-blind-validator | Final Gate | No | TBD |
| vlm-critic | Final Gate | No | TBD (DROPPED for now — see Runtime Model, below) |

## Runtime Model

`scripts/codex-harness` is the orchestrator (not yet built in this repo —
ships in Phase 2, CX-21). It never writes source code itself (Iron Law 3
substitute, above). It only:

- creates/removes git worktrees (`scripts/lib/dispatch-agent.sh`, CX-22),
- assembles prompts (skill body + agent role file + instincts + session
  memory + scratchpad + the prior phase's `## Next Phase Input`),
- invokes `codex exec --profile <role> --cd <worktree> --sandbox
  workspace-write --output-schema <phase-verdict-schema.json> "<assembled
  prompt>"`,
- parses the verdict JSON (`scripts/lib/verdict-parse.py`, CX-23) and
  writes `pipeline-state/{task-id}/{phase}.md`,
- decides the next phase per the Pipeline Phase Order above
  (`scripts/lib/phase-order.sh`, CX-25).

**Parallel dispatch** (Best-of-N, multi-slice Build) becomes N parallel
`codex exec` invocations, one per worktree, backgrounded by the
orchestration script (`&` + `wait`) — this mirrors the Claude harness's
"parallel subagent calls in a single message" default dispatch mode. Codex
has no visible-team/tmux-pane equivalent; every dispatch here is the
parallel-subagent default.

**Runtime state** lives under `$CODEX_HOME/harness-data` (defaults to
`~/.codex/harness-data`, overridable) — this preserves the same
seed-vs-runtime split the Claude harness uses for `$CLAUDE_PLUGIN_DATA`:
this repo ships only curated seed (skills, agent TOML configs, seeded
memory index config); runtime state (pipeline-state, session-memory,
metrics, per-task learning artifacts) is never committed back to this repo.

**Vision/screenshot-diff work** (`vlm-critic`, `design-qc`) is DROPPED for
now — Codex's tool surface for vision/computer-use was not confirmed in the
verified doc set at plan time (`<unverified>`); revisit after a dedicated
probe (see PLAN.md §5 CX-90/CX-91 and §1 "What is impossible").

## Sandbox / Permission Posture

`codex exec` defaults to **read-only**. Build-phase invocations must
explicitly request `workspace-write` via the orchestration script's `codex
exec --sandbox workspace-write` flag. `danger-full-access` is never used
outside a documented, isolated runner — treat any invocation requesting it
as a stop-and-report event, same posture as this harness applies to
bypassing a blocked gate (see Iron Law 8, above).

## Autonomous Intelligence

Three systems make the pipeline self-improving, ported at full fidelity
from the Claude harness (their real mechanism was always
orchestrator-side/script-side string concatenation, not a hook mutation —
so nothing is lost in the port):

| System | Scope | Purpose |
|--------|-------|---------|
| **Pipeline Scratchpad** | Within one pipeline | Agents share discoveries in real-time via `pipeline-state/{task-id}/scratchpad/` |
| **Session Memory** | Across compaction | Engineering context survives context compression |
| **Continuous Learning** | Across pipelines | Observations → instincts → better agent prompts (auto-invokes `$harness-learn`) |

Instinct injection, agent memory, and session-memory splicing into a spawn
prompt are done entirely by the orchestration script's prompt-assembly step
(`scripts/lib/instinct-inject.py`, a port of the source harness's
`hooks/_lib/instinct_loader.py` resolver logic) — this runs BEFORE each
`codex exec` call and concatenates the rendered `## Learned Patterns` block
into the assembled prompt, in the same position the source harness's Agent
Spawn protocol uses: skill → agent definition → instincts → agent memory →
session memory → scratchpad → scratchpad-write-instruction. Codex hooks
parse but skip `prompt`/`agent` handler types and have no confirmed
`modified_tool_input` equivalent, so this cannot be a mid-session hook
mutation on Codex — it must be, and always effectively was, orchestrator-side
string concatenation before the agent ever sees the prompt.

## Definition of Done

A unit of work is done when ALL of the following hold:

- Every acceptance criterion is covered by a failing-then-passing test in
  the diff (Iron Law 1).
- All reviewers (code-reviewer, security-engineer, product-reviewer as
  applicable) return an APPROVE verdict.
- The pull request is merged.
- Reflection has run and produced an observation (Iron Law 7) — no
  exceptions, successes and failures both.

