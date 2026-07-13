---
name: "security-review"
description: "Inline security audit pass over your own diff: OWASP Top 10, secrets, auth/authz, dependency vulns. Run this on yourself before verify/ship — there is no separate security-engineer to spawn."
context: fork
---

# Security Review (inline self-audit)

## § 0 — SAST Triage Layer (Pre-Rubric)

> **Runs BEFORE the OWASP rubric below.** Triage is purely additive: it ingests
> SAST output (Semgrep, CodeQL, others producing SARIF), assigns each finding
> a `keep | drop | unsure` verdict with mandatory rationale, merges
> `keep`+`unsure` into the working set, and logs every decision to a
> forensic JSONL stream. The OWASP rubric is unchanged and runs INDEPENDENTLY
> alongside the triage block.

### § 0 — Bypass switch

When `CLAUDE_DISABLE_SAST_TRIAGE=1`, § 0 exits early with `TRIAGE_BYPASSED`
BEFORE detection (rung 1 is never inspected). The main `metrics/$SESSION/sast-triage.jsonl`
is NOT touched. A single bypass record is written to a DISTINCT ledger
`metrics/$SESSION/sast-triage-bypass.jsonl` (verdict: `BYPASSED`,
reason: `CLAUDE_DISABLE_SAST_TRIAGE=1`). Stderr emits
`SAST triage bypassed via CLAUDE_DISABLE_SAST_TRIAGE`. OWASP rubric proceeds
unchanged.

### § 0.1 — Detection ladder (4 rungs, first hit wins)

| Rung | Source | When |
|---|---|---|
| rung 1 | `$CLAUDE_SAST_SARIF_PATH` (operator override) | CI providing pre-computed SARIF |
| rung 2 | `$state_dir/{task_id}/scratchpad/sast-*.sarif` | Earlier pipeline step staged SARIF |
| rung 3 | direct semgrep subprocess (`semgrep --sarif --json --quiet -- <changed>`) on `git diff main...HEAD` files | On-demand fallback when rungs 1-2 absent. Bounded by `CLAUDE_SAST_SEMGREP_TIMEOUT_SEC` (default 60s). `shutil.which("semgrep") is None` → rung skipped silently. |
| rung 4 | None | Tool not installed and no staged SARIF — emit `TRIAGE_NO_INPUT`, OWASP rubric proceeds |

If any rung resolves to a file/source but parsing fails (corrupt JSON, SARIF
shape error, semgrep crash), the runner logs the rung that fired plus the
parse error class (`json-decode-error | sarif-shape-error | semgrep-shape-error
| subprocess-failed`) and falls through. If ALL rungs that resolved produced
parse failures, § 0 emits `TRIAGE_PARSE_FAILED` (DISTINCT from
`TRIAGE_NO_INPUT`) and OWASP rubric proceeds.

### § 0.2 — Parsing & severity normalization

Findings filtered to changed-files-only at parse time (NOT triaged, NOT logged
for unchanged files).

| Tool | Raw | Normalized |
|---|---|---|
| Semgrep | `ERROR` | `CRITICAL` |
| Semgrep | `WARNING` | `HIGH` |
| Semgrep | `INFO` | `LOW` |
| SARIF (CodeQL etc.) | `error` | `HIGH` |
| SARIF | `warning` | `MEDIUM` |
| SARIF | `note` | `LOW` |
| SARIF | `none` | `INFO` |

Unknown severities → `INFO` + stderr warning.

### § 0.3 — Triage iteration (run this loop yourself, inline)

> This section is the iteration template you execute inline while running
> this skill — `for each finding`, render the prompt below, produce the
> strict-JSON verdict, validate its shape, and append the result to the
> merged working set. There is no separate reviewer role calling this loop
> on your behalf.

For each finding produced by § 0.2, work through this decision once
(per-finding for v1; batching is a v2 follow-up):

```
You are triaging a SAST finding for inclusion in a security review.

Finding:
  Tool: {tool}
  Rule: {rule_id}
  Severity: {sast_severity}
  File: {file}:{line}
  Message: {message}
  Code:
    {snippet}

Decision rules:
- keep:   This is a real vulnerability or potential vulnerability.
- drop:   This is a confirmed false positive. Provide a 1–2 sentence rationale.
- unsure: You cannot determine with confidence. Default here when in doubt.

Output (strict JSON, no prose):
{
  "verdict": "keep" | "drop" | "unsure",
  "rationale": "1–2 sentence explanation. MUST NOT be empty. MUST NOT be 'N/A' or similar."
}

Conservatism rule: When in doubt, choose `unsure`. A wrong `drop` ships a vulnerability.
```

Strict-JSON output contract: `verdict ∈ {keep, drop, unsure}`. Rationale must
be non-empty, non-`N/A`, ≥ 8 tokens, and not in the parser's stop-list. A
malformed output gets force-rewritten to `unsure` with a system rationale.

### § 0.4 — Merge into working set

`keep` + `unsure` findings render into a `## SAST Triage Findings (Pre-Rubric)`
block PREPENDED to the review. `drop` findings are excluded from the
merge block but ARE recorded in the JSONL ledger.

```markdown
## SAST Triage Findings (Pre-Rubric)

### keep (N findings)
- **{rule_id}** `{file}:{line}` (sast={sast_severity}) — {message}
  - Triage rationale: {rationale}

### unsure (M findings)
- **{rule_id}** `{file}:{line}` (sast={sast_severity}) — {message}
  - Triage uncertainty: {rationale}
```

### § 0.5 — Telemetry JSONL

Every triage decision (incl. `drop`) appends one record to
`metrics/$SESSION/sast-triage.jsonl`:

| field | description |
|---|---|
| `ts` | unix seconds |
| `session_id` | `$CLAUDE_SESSION_ID` |
| `task_id` | pipeline task-id |
| `rule_id` | tool rule identifier |
| `tool` | `semgrep` / `codeql` / `other` |
| `file` | changed file path |
| `line` | line number |
| `sast_severity` | normalized severity |
| `verdict` | `keep` / `drop` / `unsure` |
| `rationale_excerpt` | first 200 chars of rationale, single-line |
| `rationale_full_hash` | `sha1:` + sha1 of full rationale |

Telemetry write failure logs to stderr but does NOT block triage.

### § 0.6 — Operator-surface env vars

| Env var | Effect |
|---|---|
| `CLAUDE_DISABLE_SAST_TRIAGE=1` | Skip § 0 entirely; write one record to bypass ledger |
| `CLAUDE_SAST_SARIF_PATH` | Pre-staged SARIF — operator override; rung 1 wins |
| `CLAUDE_SAST_SEMGREP_TIMEOUT_SEC` | Override 60s default for rung-3 subprocess |

---

## What This Skill Does

A single-thread contractor has no separate security-engineer role to
spawn — this skill is the security checklist you run against your OWN
diff, in the same session that wrote it, before verify/ship/handoff.

## Current Context

- Branch: !`git branch --show-current`
- Changed files: !`git diff main...HEAD --name-only 2>/dev/null || echo 'N/A'`
- Diff stats: !`git diff main...HEAD --stat 2>/dev/null || echo 'N/A'`

## When to Run

- After the build/fix work is functionally complete (`$harness-code-review`
  self-review has already run or is about to run in the same session —
  order between the two does not matter, both are read-only passes over
  the same diff).
- APPROVE required before advancing to verify/ship or writing
  `Done (verified)` into a `HANDOFF.md`.

## Process

### 1. Audit the Diff

Assess the diff against the Security Checklist below:

- OWASP Top 10 vulnerabilities (injection, XSS, CSRF, etc.)
- Authentication and authorization (are auth checks present and correct?)
- Input validation at system boundaries
- Secrets in code or commits (API keys, tokens, passwords)
- Dependency vulnerabilities (`npm audit` / `bundle audit`)
- Secure cookie flags, HTTPS enforcement
- Content-Type validation on file uploads
- If the diff touches `learning/`, `agent-memory/`, or `hooks/`/`.codex/hooks/`,
  ALSO apply the Agentic Surface Gate checklist below (memory poisoning,
  instinct poisoning, tool misuse, goal hijacking).

Assign a verdict with severity levels: CRITICAL, HIGH, MEDIUM, LOW.
APPROVE if no CRITICAL, HIGH, or MEDIUM findings. CHANGES_REQUESTED (fix
it yourself) if any CRITICAL, HIGH, or MEDIUM findings exist. LOW and
INFO findings are noted but do not block.

### 2. Act on Findings

- **APPROVE** (no CRITICAL/HIGH/MEDIUM): proceed to the next step
  (verify/ship/handoff).
- **CHANGES_REQUESTED**: fix the CRITICAL/HIGH/MEDIUM findings yourself,
  in this same session. Re-run the checklist against the updated diff.

## Security Checklist

- [ ] No SQL/NoSQL injection vectors
- [ ] No XSS vulnerabilities (output encoding, CSP)
- [ ] No hardcoded secrets or credentials
- [ ] Auth checks on all protected routes/endpoints
- [ ] Input validation on external boundaries
- [ ] Dependencies free of known CVEs (`npm audit` / `bundle audit`)
- [ ] Secure cookie flags (HttpOnly, Secure, SameSite)
- [ ] No sensitive data in logs or error messages
- [ ] HTTPS enforced for all external communication
- [ ] File upload validation (type, size, content)

## Agentic Surface Gate

Changes touching the agent control plane — `learning/`, `agent-memory/`,
or `hooks/`/`.codex/hooks/` — get an extra pass covering the Agentic
OWASP Top 10 concerns: memory poisoning (a written instinct/memory file
that injects instructions rather than describing a pattern), instinct
poisoning (a promoted instinct that encodes an unsafe shortcut), tool
misuse (a hook or skill granted broader tool access than its task
needs), and goal hijacking (prompt content in a memory/scratchpad file
that could redirect a future session's objective). There is no separate
enforcement hook wired for this on the codex-harness side today — this
is a self-audit discipline, not a blocking gate.

## Supply Chain Security (if Trail of Bits plugins available)

When Trail of Bits security skills are installed (`supply-chain-risk-auditor`, `variant-analysis`, `differential-review`):

- [ ] Run `supply-chain-risk-auditor` on new/updated dependencies (typosquatting, maintainer compromise, post-install scripts)
- [ ] If a vulnerability is found, run `variant-analysis` to find similar patterns across the codebase
- [ ] Use `differential-review` for security-focused diff analysis on high-risk changes

These complement `npm audit`/`bundle audit` by covering supply chain threats that package auditors miss.

## Severity Grading

Every finding MUST be assigned a severity. Use the calibration table below:

| Severity | Definition | Examples | Blocks? |
|----------|-----------|----------|---------|
| CRITICAL | Security vulnerability or data loss risk | SQL injection, exposed secrets, auth bypass | Yes |
| HIGH | Correctness bug or significant design flaw | Missing error handling, broken invariant, SOLID violation | Yes |
| MEDIUM | Code quality issue causing maintenance pain | DRY violation across files, unclear naming, missing edge case test, unnecessary coupling | Yes |
| LOW | Minor improvement or style preference | Variable rename suggestion, comment improvement | No |
| INFO | Observation, context, or positive feedback | "Nice pattern," "FYI this also handles X" | No |

**Verdict rule:** APPROVE if no CRITICAL, HIGH, or MEDIUM findings. CHANGES_REQUESTED if any CRITICAL, HIGH, or MEDIUM findings exist. LOW and INFO are noted but do not block.

**In-cycle enforcement:** CHANGES_REQUESTED findings are fixed in this
same session, never deferred to a follow-up ticket or shipped
known-broken. If a finding is genuinely orthogonal (different attack
surface, different module), mark it INFO, not MEDIUM.

## Phase Output

```
Verdict: APPROVE / CHANGES_REQUESTED
Next: If APPROVE → proceed (verify/ship/handoff)
      If CHANGES_REQUESTED → fix in this session, re-run this checklist
Findings: [severity-rated findings: CRITICAL, HIGH, MEDIUM, LOW]
```
