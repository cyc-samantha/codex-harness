---
name: "build-implementation"
description: "Structured Build-phase TDD implementation: RED-GREEN-REFACTOR per slice, mutation kill loop. Use when implementing acceptance criteria after a plan is approved."
context: fork
agent: software-engineer
argument-hint: "Acceptance criteria or story to implement"
---

# Build Implementation

## What This Skill Does

Prescribes the exact procedure for build work: consume the per-AC failing-test stub list (from a plan you wrote or one handed off in `HANDOFF.md`), implement each slice via the ATDD cycle (two test invocations per slice plus a mutation gate), and enforce cohesion-based shape rules continuously.

## Where This Runs

Do this work inside a git worktree (see AGENTS.md § Worktree + Commit
Protocol) — never directly against the checkout you started the session
in. There is no separate agent to dispatch this to; you read this file
and execute it yourself, in the worktree, single-thread.

## Procedure

### Step 1: Read AC Test Stubs from the Plan

Before writing any code:
1. Open `$state_dir/{task-id}/plan.md` and locate the **Failing Test Stubs (per AC)** section the architect produced.
2. For each AC in this slice, the stub list names: test file path, test name, assertion intent.
3. **If any AC has no stub, halt immediately** — surface the gap to the architect and request a stub. Implementation cannot begin without a complete stub list.
4. The stub list IS your implementation plan. Three test invocations per slice — not three per AC, three per slice. See `protocols/atdd-procedure.md` for the full cycle.

### Step 1b: Install Required Dependencies

If the implementation requires new packages not yet in `package.json`:
1. Install the package: `npm install <package>` (or equivalent)
2. Verify the installation: `npm ls <package>` (or equivalent)
3. Commit `package.json` and lock file separately: "chore: add <package> for <reason>"
4. Proceed with the batched-RED step — the first failing batch validates the dependency works.

If a handed-off `HANDOFF.md` names a dependency in its `Next Actions`, install it here. If you discover a needed dependency during implementation, install it at that point.

### Step 1c: Write Contract Assertions (Tier 0 — Spec-as-Contract)

Inserted between "Read AC Test Stubs" and "Batched RED". Required for every slice that touches a contract listed in `$state_dir/{task-id}/intake.md` § Contracts Touched. If `(none)` was recorded at intake, skip this step (no public surface changed).

For each contract in the list:

1. Author a **runtime assertion** at the module port that encodes the contract:
   - **Public function signatures** → input/output type guards (e.g., `assertSchema(Input, x)` at the start, `assertSchema(Output, y)` before returning).
   - **JSON schemas** → schema validators (`zod`, `pydantic`, `ajv`, `cerberus`) at the boundary; reject malformed input with structured errors.
   - **OpenAPI paths** → request/response validation middleware (`openapi-validator`, `dredd`, `Pact`) wired into the route handler.
   - **DB schemas** → constraints declared in the migration (NOT NULL, FOREIGN KEY, CHECK) AND mirrored in the ORM/data-access layer for fail-fast at write time.
   - **Invariants** → a runtime check at the place the invariant must hold (`invariant(predicate, message)`), authored as a re-usable helper not a one-off `if`/`throw`.

2. Author a **failing contract test** for each assertion in a `*.contract.spec.{ts,js,py,rb,go}` file (Tier 0 in `protocols/engineering-invariants.md` § Proof of Correctness):
   - The test feeds a *deliberately invalid* input and asserts the contract rejects it with the structured error.
   - The test feeds a *valid* input and asserts the contract accepts it and the downstream behavior runs.

3. Run the suite ONCE before any implementation. Capture the **Tier-0 RED output** — the contract assertions must fail because the production code that wires them is not yet written. This is the audit artifact for Tier 0.

The Tier-0 RED output is a separate capture from the Step-2 BATCHED RED output. Both are required as audit artifacts for the slice (per `protocols/atdd-procedure.md` § Audit Trail).

### Step 1d: Property-Based Tests (out of scope for this kit)

The dedicated property-based-testing skill was cut in the Phase 8 cull
(the contractor kit does not carry a `pbt-engineer` role or a
`property-based-test` skill) — this step is a no-op here. If a function
you are implementing has an obvious property worth asserting
(idempotence, inverse, an oracle comparison, a metamorphic relation) and
the project already has a property-testing library installed (`fast-check`,
`hypothesis`, `PropEr`, etc.), write it inline as an ordinary test in
Step 2 rather than invoking a separate procedure for it.

### Step 2: Implement Slice via ATDD (Two test invocations per slice)

Follow the ATDD Protocol in `protocols/atdd-procedure.md`:

1. **BATCHED RED**: Write every AC test as one batch (the architect's stubs verbatim). Run the suite ONCE. Capture the RED output. Verify each test fails for the right reason — the named behavior is absent. The Tier-0 contract tests authored in Step 1c are also part of this batch (they are still RED unless the contract assertion was implementable in isolation in Step 1c).
2. **IMPLEMENT CLEANLY**: Write production code that is correct AND well-shaped on the first pass. Cohesion rules (one-thing-per-function, CC ≤ 5, nesting ≤ 2, DRY on 2nd occurrence) apply *as you write*, not in a separate cleanup pass. Choose intent-revealing names from the start; extract duplication on the 2nd occurrence as it appears. Run the suite ONCE when done. Capture the GREEN output. After the suite run inside IMPLEMENT CLEANLY, on RED follow Step 4a–4c.
3. **MUTATION GATE**: Run mutation testing on changed lines (Stryker / Mutant / mutmut, or the manual fallback in `skills/verify/SKILL.md`). Score >= 70% required against the **union suite** (architect stubs + adversarials from Step 2b). If <70%, run the active, time-boxed **Mutation Kill Loop** — see atdd-procedure.md step 4 Mutation Kill Loop for the full canonical spec (pointer only; do NOT re-specify here). The loop exits with OUTCOME `REACHED` (>= 70%, continue), `EXHAUSTED` (time budget spent), or `NO_PROGRESS` (two consecutive zero-kill rounds); non-REACHED outcomes fail the gate in-cycle per Iron Law 6.
4. **COMMIT** with the three audit artifacts: batched RED output, GREEN output, mutation report.

**Exception cycles** — bug fixes, complex algorithmic logic, and security-sensitive code retain per-behaviour RED-GREEN. See `protocols/atdd-procedure.md` § When per-behaviour TDD Still Applies (Exceptions). For those cases follow `skills/bug-fix/SKILL.md` instead of the batched cycle.

**Decision Ladder (ADVISORY — shapes how you write; gates nothing).** Before writing any new production code, walk these seven rungs: (1) Does this need to exist at all? (YAGNI) (2) Is it already in this codebase? Reuse it. (3) Does the standard library do it? (4) Is there a native platform feature for it? (5) Does an already-installed dependency cover it? (6) Can it be one line? (7) Only then: write the minimum that works. The ladder does not replace understanding the problem — apply it after comprehension, not instead. See `rules/core.md` § Code Shape Rules for the enforced per-language line caps and complexity limits; this note cross-references them rather than restating them.

### Step 2.5: Edit Format (unified diff for existing files)

Build agents emit **all edits to existing files as unified-diff hunks** applicable via `git apply`. Inspired by Aider's udiff method (https://aider.chat/docs/unified-diffs.html) — the udiff format reduces lazy / placeholder edits by anchoring every change to a verbatim context window.

Contract:

- **Edits to existing files**: emit a unified diff. Before commit, `git apply --check <patch>` MUST pass — if it fails, the hunks are corrupt and the edit is rejected.
- **Write tool reserved for net-new files only.** Do NOT use Write to overwrite an existing file; use a udiff hunk instead. (NotebookEdit applies to `.ipynb` Jupyter notebooks per existing tooling; udiff applies to text source files only.)
- **Encoding**: patches MUST be UTF-8, LF line endings, no BOM.
- **No placeholders.** Hunks MUST NOT contain `...` placeholders or `TODO: add ...` comments. The diff is the change — never abbreviated, never elided.

This step is contract-only; the actual hunk authoring happens inside Step 2 (IMPLEMENT CLEANLY) and Step 4b (refinement). Step 2.5 names the format so reviewers and the patch-critic can reject non-conforming edits up front.

### Step 2b: Adversarial Test Categories (greenfield ACs default-on, refactor slices env-gated)

After Step 2's IMPLEMENT step lands GREEN and BEFORE the MUTATION GATE finalises, generate adversarial tests that probe edge cases the architect's stubs do not cover. Adversarials are AC-adjacent edge probes — they belong AFTER architect stubs are GREEN, not before. Inspired by AlphaCodium (arXiv 2401.08500) test-iteration loop.

**Bug-fix slices SKIP this step entirely.** For bug-fix work, the repro test IS the contract — adversarial probing belongs in greenfield AC implementation, not regression closure. See `skills/bug-fix/SKILL.md` for the per-behaviour cycle that applies instead.

**Refactor slices.** For refactor slices, Step 2b is opt-in (default OFF — soak window). When enabled, generate adversarials with **cap=3** (not the greenfield cap=5) — refactors change implementation, not contract, so a tighter cap bounds cycle time while still surfacing implementation regressions. The 5-category walk and discipline rules below apply unchanged; only the cap differs. Enable per pipeline by exporting `CLAUDE_ADVERSARIAL_TESTS_REFACTOR=1` in the build agent's environment. The flag is additive over the master kill-switch — `CLAUDE_ADVERSARIAL_TESTS=0` overrides any value of `CLAUDE_ADVERSARIAL_TESTS_REFACTOR` and skips Step 2b regardless.

**Precedence truth table.** The two env vars and the slice's task class compose as follows. The master kill-switch wins; the refactor opt-in is additive only when the master is unset/`1`; bug-fix always skips:

| `CLAUDE_ADVERSARIAL_TESTS` | `CLAUDE_ADVERSARIAL_TESTS_REFACTOR` | task class | Step 2b behavior |
|---|---|---|---|
| `CLAUDE_ADVERSARIAL_TESTS=0` | any | any | SKIPPED (master kill-switch wins) |
| unset / `1` | unset / `0` | greenfield | RUNS, cap=5 |
| unset / `1` | `CLAUDE_ADVERSARIAL_TESTS_REFACTOR=1` | refactor | RUNS, cap=3 |
| unset / `1` | unset / `0` | refactor | SKIPPED (soak default-off) |
| any | any | bug-fix | SKIPPED (bug-fix iron law) |

**Escape hatch.** Set `CLAUDE_ADVERSARIAL_TESTS=0` in the environment to disable Step 2b — this skips Step 2b entirely on every task class (greenfield, refactor, bug-fix). The hatch exists for the soak window (default-on for greenfield) so cycle-time impact can be measured before flipping to mandatory; it is the one-line revert path if adversarial generation introduces unexpected runtime cost.

**Procedure.** Generate **3-5 adversarial tests** (HARD CAP at 5 — bound the cycle time). Walk the categories below in order, stop at 5 once the cap is reached even if later categories were not exercised. Each adversarial follows **RED-then-GREEN** — write the test, run the suite, confirm it fails for the right reason, then implement (or correct production code) until it passes. This is the same audit-trail contract as the architect's stubs; a captured RED is the audit artifact.

Walk these 5 categories IN ORDER:

1. **Boundary values** — off-by-one (`n-1`, `n`, `n+1`), empty collection, single-element, max int / max string length where the language allows.
2. **Null / empty / undefined** — every input where the type allows. Skip if the type forbids (e.g., a non-nullable `int` parameter in Kotlin needs no null adversarial).
3. **Malformed input (parser-level only)** — malformed JSON, malformed dates, encoding edge cases (BOM, mixed UTF-16, lone surrogates). Only when changed code parses external input — skip for code that receives already-parsed structures.
4. **Error-path coverage** — for every catch / rescue / except block on changed lines, write one test that triggers it and asserts the block's claimed behavior. The catch block exists to do something — assert it does that thing.
5. **Concurrency races** — ONLY when changed code touches shared mutable state (module-level mutable, singleton instance state, file lock, DB row write without transaction). Skip for pure / per-request / per-instance code.

**Discipline rules.**

- **passes immediately = delete.** An adversarial that goes GREEN on its first run without any production-code change has no diagnostic value — the existing tests already cover the case, or the named edge does not actually exist on the changed lines. Delete it; do not keep it as a vanity test.
- **HALT if adversarial reveals contract gap.** If an adversarial surfaces a behavior the AC does not specify (e.g., what should happen on negative input when the AC is silent), HALT and surface to the architect. Do not invent the contract — the architect owns the spec, the engineer owns the implementation.

**PBT overlap.** When a function already has property-based tests covering it (whether you wrote them earlier in this slice or they pre-existed), **cap reduces from 5 to 3** for that function — property tests already exercise boundary values and null/empty cases; adversarials should focus on **error-path + concurrency**, which property tests cover poorly. Detection is mechanical — file glob `tests/**/*.property.{spec,test}.*` next to the changed file → cap=3.

After adversarials are GREEN, return to Step 2's MUTATION GATE on the **union suite** (architect stubs + adversarials).

### Step 2c: In-Loop Security Scan (secret hard-block + SAST/dep auto-fix-or-escalate)

Inserted between Step 2b and Step 2d. A first-pass shift-left scan runs automatically on every `git commit` inside the worktree via the `build-loop-scan.sh` PreToolUse:Bash hook — it scans the staged diff, HARD-BLOCKS an introduced secret before the commit object is created, and surfaces SAST/dependency findings advisory. Default ON. Triad verdicts: `BUILD_SCAN_PASSED`, `BUILD_SCAN_SKIPPED`, `BUILD_SCAN_BLOCKED`. Artifact: `$state_dir/{task-id}/build-artifacts/build-loop-scan-report.json` (written on every commit attempt).

**Why this is distinct from the second-pass gate.** This in-loop gate catches the obvious early; it does NOT replace, narrow, or skip security review. **Security-review remains the authoritative second-pass gate** — it runs its full OWASP rubric + SAST triage + secrets + dependency audit after `BUILD_COMPLETE`. The phase order `Build → Security Review → Final Gate` is unchanged.

**Escape hatch.** Set `CLAUDE_DISABLE_BUILD_LOOP_SCAN=1` to bypass — the hook emits a stderr notice, writes one bypass-ledger JSONL line, and exits 0 even with a staged secret. The hatch matches the canonical `CLAUDE_DISABLE_*=1` shape. The second-pass gate still catches anything real, so the bypass is recoverable.

**Auto-fix posture.**

- **Secret (`BUILD_SCAN_BLOCKED`, exit 2)** → HALT. Never auto-commit a secret. Move the literal to an env var / secret store, re-stage, re-commit. The block is regex-based (canonical patterns in `hooks/_lib/build_loop_scan.py`) so it is tool-independent — a missing scanner never disables it.
- **SAST/dep finding that is mechanical AND non-breaking** (e.g. a flagged `eval()` with an obvious safe rewrite, a patch-level dependency bump) → auto-fix in-loop and re-commit.
- **Ambiguous OR breaking finding** → do NOT guess. Escalate to security-review (the second-pass gate) rather than invent the contract.

**2am breadcrumb.** If a known secret was NOT blocked in-loop: (1) confirm the commit ran inside `.claude/worktrees/agent-*`; (2) check `build-loop-scan-report.json` at `$HARNESS_DATA/pipeline-state/${CLAUDE_TASK_ID:-inline-build-scan-gate}/build-artifacts/build-loop-scan-report.json` — the hook uses `CLAUDE_TASK_ID` env when available and falls back to `inline-build-scan-gate`; check `verdict` + `staged_file_count` — a `staged_file_count` of `0` means the staged-diff read targeted the wrong repo, check the `cwd` resolution in `hooks/_lib/build_loop_scan_cli.py`; (3) `grep CLAUDE_DISABLE_BUILD_LOOP_SCAN` the env and the bypass-ledger; (4) security-review is the backstop — the secret is still gated before Ship.

### Step 2d: DOM Smoke

Inserted between Step 2b and Step 3. Authors a runtime smoke check via Chrome DevTools MCP: navigate each changed route, fail Build on console `level: error` or network `status >= 400` (after the inline ignore-list filter). Default ON. The escape hatch is `CLAUDE_DOM_SMOKE=0`. Triad verdicts: `DOM_SMOKE_PASSED`, `DOM_SMOKE_SKIPPED`, `DOM_SMOKE_FAILED`.

**2am breadcrumb.** If DOM smoke fails on every Build and nothing in the diff explains it → (1) check the ignore-list regex below, (2) check `.claude/dom-smoke-ignore.json`, (3) check sentinel state `$state_dir/{task-id}/.dom-smoke-warm`, (4) set `CLAUDE_DOM_SMOKE=0` to confirm Step 2d is the offender.

Note: `mcp__chrome-devtools__*` tool calls outside the four-entry allowlist are advisory-blocked only (v2.1.140); enforcement promotes to hard-block when the per-spawn `thinking` field exposure ships.

**Procedure.**

1. **Escape hatch.** If `CLAUDE_DOM_SMOKE=0` is set → emit `DOM_SMOKE_SKIPPED reason=env-hatch` and return. Default ON.

2. **Comparison base.** Compute the changed-files list against the slice's actual delta from `main`:

   ```bash
   CHANGED=$(git diff --name-only $(git merge-base HEAD main)...HEAD)
   ```

   The `merge-base ...HEAD` form is REQUIRED — it pins the comparison to the slice's true delta against `main`, even when the worktree contains cherry-picked prior-slice commits. Diffing against bare `HEAD` (no merge-base, no revision-range) is FORBIDDEN — it returns only uncommitted changes and misses every committed file in the slice.

3. **Path-glob trigger.** Match `$CHANGED` against the five frontend globs. If none match → `DOM_SMOKE_SKIPPED reason=no-changed-routes` and return.

   - `app/**`
   - `src/**`
   - `pages/**`
   - `components/**`
   - `**/*.{tsx,jsx,vue,svelte,html,css}`

4. **Resolve routes.** Use the project's route resolver (Next.js `app/`, Vite router, Astro `src/pages/`, etc., per `skills/design-qc/SKILL.md` § Step 5) to map matched files to URL routes. Always include `/`. If no resolver applies → `DOM_SMOKE_SKIPPED reason=no-route-resolver` and return.

5. **Dev-server lifecycle.** Install, build, start the dev server bound to loopback only, poll the health endpoint, capture the process group for SIGKILL-safe teardown:

   ```bash
   # DUPLICATES skills/design-qc/SKILL.md:46-90 — see plan chrome-devtools-mcp-wire M2
   # rationale; future helper extraction is a separate pipeline.
   HOST=127.0.0.1 npm install && npm run build
   # Use setsid so we can kill the process group on cleanup (SIGKILL-safe).
   HOST=127.0.0.1 setsid npm run dev > /dev/null 2>&1 &
   DEV_PID=$!
   echo "$DEV_PID" > "$state_dir/{task-id}/.dev-server.pid"
   for i in $(seq 1 30); do
     curl -fsS http://127.0.0.1:3000/ >/dev/null 2>&1 && break
     sleep 1
   done
   trap 'kill -- -$DEV_PID 2>/dev/null; rm -f "$state_dir/{task-id}/.dev-server.pid"' EXIT
   ```

   Framework-specific overrides: Vite `--host 127.0.0.1`, Nuxt `NITRO_HOST=127.0.0.1`, Astro `--host 127.0.0.1`. Step 2d MUST verify dev server is bound to loopback only — if `ss -tlnp` (or `lsof -iTCP -sTCP:LISTEN`) shows 0.0.0.0 binding, emit `DOM_SMOKE_FAILED reason=dev-server-non-loopback`.

   Reflect phase reaps stale `.dev-server.pid` files across `pipeline-state/*` directories.

6. **MCP unavailable — sentinel escalation.** On first invocation:
   - If `npx -y chrome-devtools-mcp@0.26.0` exceeds 90s OR the MCP server returns "server unavailable" → emit `DOM_SMOKE_SKIPPED reason=mcp-unavailable-first-run` AND `touch $state_dir/{task-id}/.dom-smoke-warm` (the sentinel). Return.
   - On any subsequent invocation: if `$state_dir/{task-id}/.dom-smoke-warm` exists AND MCP is unavailable → emit `DOM_SMOKE_FAILED reason=mcp-unavailable-after-warm`. HALT Build. (No silent skip — the sentinel proves MCP worked once in this task.)

7. **Per-route smoke.** For each resolved route, invoke the Chrome DevTools MCP tools in **invocation form** (double-underscore + hyphen, server segment `chrome-devtools` matching the npm package name):

   - `mcp__chrome-devtools__navigate_page` — navigate the running dev server to the route.
   - `mcp__chrome-devtools__list_console_messages` — read the console event stream.
   - `mcp__chrome-devtools__list_network_requests` — read the network event stream.

   Note: this is the *invocation* form. The allowlist form `mcp_chrome_devtools_*` (underscore-flat) lives in `agents/frontend-engineer.md` frontmatter and is NOT interchangeable with the invocation form.

8. **Inline ignore-list regex** (applied to console `message` and network `url` BEFORE the failure check). False positives are fixed in-cycle by extending this list — no follow-up tickets:

   - `^Warning: ReactDOM\.render`
   - `^Warning: .* is deprecated`
   - `\[HMR\]`
   - `Download the React DevTools`
   - `\[Fast Refresh\]`
   - `Lighthouse`
   - Network URLs matching `://[^/]*\.(googletagmanager|google-analytics|doubleclick|hotjar)\.`
   - `data:` and `blob:` scheme URLs

   Project-level extensions live in `.claude/dom-smoke-ignore.json` (additive).

   **Validate ignore-list patterns.** Before applying any pattern (inline or from `.claude/dom-smoke-ignore.json`), reject patterns matching `^(\.\*|\.\+|\^|\$|\.|)$` (overbroad neuters). On detection → emit `DOM_SMOKE_FAILED reason=ignore-list-overbroad` and HALT Build. This prevents a malicious or careless commit from silently disabling the gate.

9. **Failure semantics.** After the ignore-filter:

   - Any console message with `level: error` → `DOM_SMOKE_FAILED`.
   - Any network request with `status >= 400` → `DOM_SMOKE_FAILED`.

   Payload shape: `{route, errors: [{type, message, url, status}]}` where `type ∈ {console, network}`, `message` is the literal console text (console errors set `url=null`, `status=null`), and `url`/`status` carry the network request data (network errors set `message=null`). Kill the dev server (`kill $DEV_PID`) and HALT Build.

10. **Success.** All routes clean → `DOM_SMOKE_PASSED`. Kill the dev server. Proceed to Step 3.

11. **Audit trail.** Write `$state_dir/{task-id}/build-artifacts/dom-smoke-report.json` with `{routes_checked, verdict, payload, sentinel_present, comparison_base}` on every invocation (PASSED, SKIPPED, FAILED).

### Step 3: Shape Check After Every File

After completing or modifying ANY file, verify the cohesion-based shape rules in `protocols/engineering-invariants.md` § Code Shape:

- One thing per function (name has no conjunction)
- CC ≤ 5, nesting ≤ 2
- DRY on 2nd occurrence
- Single public entry point per class

Hard limits for new/changed code: Ruby functions > 5 lines, TS/JS functions > 12 lines (see `protocols/engineering-invariants.md` § Code Shape for per-language table). Soft advisory smells: file > 150 lines — refactor when extraction has a real seam, leave alone when the unit is genuinely cohesive. The hook's 300-line safety net catches runaway output only.

If any hard rule is violated, refactor BEFORE moving to the next test case.

### Step 3b: Optional Tool Synthesis Escalation

If the standard toolset (Read, Grep, Glob, Bash one-liners, project-shipped scripts) is insufficient and a one-shot scratch tool would unblock progress, invoke `/harness:tool-synthesis`. Triggers (any one):

- The same lookup/transformation has been performed manually **3+ times** in this task
- No extant tool covers the operation cleanly (no `rg` pattern, no `ast-grep` rule, no project script)
- A repo-specific concern (custom DSL, generated file, codebase convention) makes off-the-shelf tools wrong

The synthesised tool lives in `${WORKTREE}/.claude-scratch-tools/`, is invoked via Bash, and is cleaned up before BUILD_COMPLETE. It NEVER reaches `main`. See `skills/tool-synthesis/SKILL.md` for the full procedure.

If a built-in tool covers it, USE IT — do not synthesise.

### Step 4: Self-Review Checklist Before Done

Before declaring the build complete:
- [ ] Every AC has at least one passing test
- [ ] Every function does one thing (name has no conjunction)
- [ ] Cyclomatic complexity ≤ 5; nesting ≤ 2
- [ ] No DRY violations (no logic duplicated 2+ times)
- [ ] New/changed functions within per-language limits (Ruby ≤ 5, TS/JS ≤ 12 — `protocols/engineering-invariants.md` § Code Shape); files > 150 lines: justified or refactored
- [ ] All tests pass
- [ ] ATDD audit trail visible (batched RED + GREEN + mutation report ≥ 70%)
- [ ] Mutation Kill Loop ran (per atdd-procedure.md step 4 Mutation Kill Loop); OUTCOME recorded as `REACHED`, `EXHAUSTED`, or `NO_PROGRESS` in the mutation report header; on non-`REACHED` the gate failed and kill-tests + residuals handed back in-cycle via `CLAUDE_MUTATION_KILL_BUDGET_SECONDS` (default 300)
- [ ] Step 2b ran with the correct cap for the slice's task class (greenfield: default-on, cap=5; refactor: opt-in via `CLAUDE_ADVERSARIAL_TESTS_REFACTOR=1`, cap=3), OR was skipped per `CLAUDE_ADVERSARIAL_TESTS=0` (master kill-switch), OR is N/A for a bug-fix slice
- [ ] Step 2c in-loop scan ran on each commit (BUILD_SCAN_PASSED/BUILD_SCAN_SKIPPED, never an unremediated BUILD_SCAN_BLOCKED), OR was bypassed per `CLAUDE_DISABLE_BUILD_LOOP_SCAN=1`
- [ ] If changes touch URL/auth/nav/WebView files: note that E2E will be required in Verify phase (see `protocols/e2e-protocol.md` trigger matrix)
- [ ] If `/harness:tool-synthesis` was invoked: `register.sh --cleanup ${WORKTREE}` ran AND `git status` shows no `.claude-scratch-tools/` entries
- [ ] Patches for edits-to-existing-files apply cleanly via `git apply --check`.

## Worktree Isolation

Build work happens in a git worktree (see AGENTS.md § Worktree + Commit
Protocol):

```bash
git worktree add "$WORKTREE_PATH" -b build/<task-id>-<slice>
```

Also read the project's tech stack pattern file if one exists at
`.agents/skills/harness-[stack]-patterns/SKILL.md` for tech-specific
guidance before starting.

**Independent slices.** A single-thread contractor works ACs one at a
time, not in parallel worktrees. If multiple ACs are independent (no
shared files), pick an order and work them sequentially — commit one
slice before starting the next. If ACs share files, this ordering
constraint is even more important: finish and commit the first slice
before touching the shared file for the second.

## Anti-Patterns

- Skipping the mutation gate → BLOCKED (a green suite is not the deliverable; the mutation report is)
- Implementing before the batched-RED output is captured → BLOCKED (RED is the audit artifact)
- Starting work when one or more ACs has no architect-produced test stub → BLOCKED (halt, surface to architect)
- Deferring shape violations to "clean up later" → BLOCKED
- Skipping the self-review checklist → BLOCKED

## Prerequisite

- The story/AC list is defined — either from a plan Claude wrote before handing off (per `HANDOFF.md` § Next Actions), or from a task description the user gave you directly
- OR: refactoring target identified (use `$harness-refactor` instead)
- OR: bug reproduction steps known (use `$harness-bug-fix` instead)

## Self-Review Gate (Mandatory Before Completion)

Before producing the Phase Output, the build agent MUST self-review:

1. **Type safety**: Run `tsc --noEmit` — zero errors
2. **Tests green**: Run full test suite — all passing
3. **Re-read all changed files** and check:
   - Function names reveal intent
   - No duplication across files (extract on 2nd occurrence)
   - Single responsibility per function/file
   - No unused imports, dead code, or commented-out blocks
   - Guard clauses over nested conditionals
4. **Fix everything found** — do not leave mechanical issues for the reviewer
5. **Shape compliance**: Hooks enforce this automatically. If a hook blocks your write, fix immediately.

The goal: the code-reviewer should find ZERO mechanical issues. Only design-level feedback should survive to review.

## Built-In Verification (Budget 5-8)

For small tasks (Complexity Budget 5-8), the build agent performs its own verification before completing:

1. **Contract tests**: Verify all new functions have tests that assert their contracts (inputs → outputs)
2. **Mutation spot-check**: For each function with conditional logic, mentally check: "If I swapped the branches, would a test catch it?" If not, add the test.
3. **Integration check**: If the change wires into an existing component, verify the integration test covers it.

This reduces the need for separate Verify and QA phases on small tasks. For Budget 9+ tasks, separate Verify and QA phases still apply.

### Step 4a: On-RED Branch

After running the suite at the end of Step 2 step (2) IMPLEMENT CLEANLY — or any subsequent same-suite invocation in this slice — if GREEN proceed to Step 5. If RED, enter the iterative-refinement loop (Step 4b). The loop is the Build phase's in-cycle fix mechanism (Iron Law 6); `/harness:bug-fix` is invoked only on exhaustion (Step 4c). Mutation-gate failure at Step 2 step (3) is NOT the trigger for this loop — it has its own remediation (add tests, return to Step 2).

### Step 4b: Iterative Refinement on RED (ReVeal, arXiv 2506.11442)

1. Append a finding to `$state_dir/{task-id}/scratchpad/{role}-build.md` with `category: test-failure-feedback`. Body:
   - (a) failing test names,
   - (b) first 20 lines of failure output,
   - (c) one-sentence root-cause hypothesis,
   - (d) attempted-edit summary (file:line ranges).
   WRITE THIS ENTRY BEFORE EDITING — count of entries IS the counter; writing after the edit double-counts. Agent crash mid-loop counts as a failed iteration (no resume semantics; the counter is durable on disk but the corresponding edit may be absent).
2. Read the scratchpad — count prior `test-failure-feedback` findings. This count is the `iteration_index` (0-based: first entry = index 0).
3. If `iteration_index + 1` reaches `MAX_ITER` (the cap from Step 4c env-var), exit to Step 4c.
4. Author a refined edit informed by the failure output AND every prior `test-failure-feedback` entry. Do NOT re-propose a hypothesis already in the log (the entries are the failed-hypothesis log).
5. Re-run the suite ONCE — the SAME suite invocation that produced the prior RED (project-default test command unless the slice scoped narrower; do not silently re-scope). GREEN → Step 5. RED → return to step 1.

Each iteration appends exactly one `test-failure-feedback` finding; the count IS the counter. Inspired by ReVeal's iterative test-feedback refinement (arXiv 2506.11442).

### Step 4c: Exhaustion — Route to /harness:bug-fix

```
MAX_ITER="${CLAUDE_BUILD_ITERATIONS:-3}"
case "$MAX_ITER" in ''|*[!0-9]*) MAX_ITER=3 ;; esac
(( MAX_ITER > 10 )) && MAX_ITER=3
# Enforced bound: 0..10 integer. Non-integer or >10 → default 3.
# =0 disables the loop entirely.
```

When the iteration counter reaches `MAX_ITER` (cap exceeded):

1. Write structured handoff to `$state_dir/{task-id}/build-handoff.md` with sections:
   - `## Failing Tests`   (names + 20-line excerpts per iteration)
   - `## Attempted Edits` (chronological, file:line per iteration)
   - `## Hypotheses Tried` (one bullet per iteration)
   All derived from the scratchpad `test-failure-feedback` entries.
2. Emit verdict `BUILD_FAILED` with
   - `reason: iteration_cap_exhausted`
   - `handoff: $state_dir/{task-id}/build-handoff.md`
   Then, in this same session, switch to `$harness-bug-fix` using the
   written handoff as the bug report. There is no separate agent to
   dispatch it to — you are the one continuing.
3. Escape-hatch: `CLAUDE_BUILD_ITERATIONS=0` SKIPS the loop entirely — first RED at Step 4a writes the handoff (single entry: current failure) and emits `BUILD_FAILED reason: iteration_loop_disabled`.

The exhaustion path is NOT deferral — `$harness-bug-fix` runs within this same session, immediately, per Iron Law 6.

## Step 5: Inline Code Review (mandatory before BUILD_COMPLETE)

After the self-review checklist passes, run `$harness-code-review`
yourself, inline, in this same session — it is a self-review checklist,
not a second reviewer.

Procedure:
1. Run `$harness-code-review` against your own diff.
2. If APPROVE → emit `BUILD_COMPLETE`.
3. If CHANGES_REQUESTED → fix the findings yourself in the same
   worktree, re-run the suite, re-run `$harness-code-review` against the
   updated diff. Max 2 rounds. If still CHANGES_REQUESTED after round 2,
   escalate to the user rather than looping indefinitely.

Run `$harness-security-review` alongside this step — do it right after
(or before; order does not matter) in this same session, still before
`BUILD_COMPLETE`.

## Verdict

After Step 5 completes:
- **BUILD_COMPLETE**: All ACs have passing tests, cohesion-based shape rules met, ATDD audit trail visible (RED + GREEN + mutation), and both `$harness-code-review` and `$harness-security-review` returned APPROVE.
- **BUILD_FAILED**: Checklist items remain unresolved OR either review never reached APPROVE after 2 rounds. List which items failed.

## Phase Output

```
Verdict: BUILD_COMPLETE / BUILD_FAILED
Next: (already ran $harness-code-review + $harness-security-review inline above) → verify/ship/handoff
Artifacts: [list of changed/created files]
Summary: [2-3 sentence contribution summary]
```

### Decision Record (Mandatory)

Include a `## Decision Record` section in the pipeline state file. This travels to the reviewer so they understand *why* before reading *what*:

```markdown
## Decision Record
- **Chose**: [approach taken]
  **Over**: [alternative considered]
  **Because**: [reasoning tied to ACs, project conventions, or engineering principles]
  **Watch**: [conditions under which this choice should be revisited]
```

Every non-trivial design choice gets an entry. Trivial choices (naming, formatting) do not. The reviewer uses this to focus their review on areas of genuine uncertainty rather than re-deriving intent from the diff.

### Context for Next Phase

Include a `## Context for Review` section in the pipeline state file:

```markdown
## Context for Review
- **Uncertainty flags**: [areas where the build agent is unsure — "I chose X but Y might be better"]
- **TDD audit summary**: [N tests added, key behaviors covered, any gaps noted]
- **Learned patterns applied**: [instincts from `$HARNESS_DATA/learning/instincts/` that influenced decisions]
- **Areas needing focus**: [specific files or patterns the reviewer should scrutinize]
```

This gives reviewers a guided entry point instead of a cold diff read.

$ARGUMENTS