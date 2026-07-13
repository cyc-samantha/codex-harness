---
name: "code-review"
description: "Inline self-review pass over your own diff before handing work back: SOLID/DRY, cohesion, test quality, complexity, naming. Run this on yourself — there is no separate reviewer to spawn."
context: fork
---

# Code Review (inline self-review)

## What This Skill Does

A single-thread contractor has no separate code-reviewer role to spawn —
this skill is the checklist you run against your OWN diff, in the same
session that wrote it, before you consider the work done or hand it back
via `HANDOFF.md`. Read the diff as if you were seeing it for the first
time: the value of a review pass is fresh eyes on judgment calls, not a
second agent.

## Current Context

- Branch: !`git branch --show-current`
- Changed files: !`git diff main...HEAD --name-only 2>/dev/null || echo 'N/A'`
- Diff stats: !`git diff main...HEAD --stat 2>/dev/null || echo 'N/A'`

## Review Focus

The build step already passed: shape hooks (blocking), type/lint checks,
and the full test suite. Do not re-verify those — focus on what requires
judgment:

- Design decisions and abstractions
- Naming clarity and intent
- DRY/SOLID at the design level (not line counting)
- Edge cases and untested scenarios
- Integration with the broader codebase

If a shape violation still made it into the diff, that is a hook gap, not
a code finding — note it and move on; do not treat it as your own review
finding.

## When to Run

- After the build/fix work is functionally complete (tests green, shape
  constraints met), before writing `Done (verified)` into a `HANDOFF.md`
  or otherwise declaring the work finished.
- Run alongside `$harness-security-review` — both are read-only passes
  over the same diff; running one right after the other in the same
  session is fine, there is no parallelism to coordinate.

## Process

### 1. Gather Context

```bash
git diff main...HEAD --stat
git log main...HEAD --oneline
```

### 2. Review Against the Checklist

Walk the diff hunk by hunk against the Review Checklist below. For each
finding, assign a severity (Severity Grading) and note whether it was
preventable at write-time (Preventability Classification) — that record
feeds a later `/harness:learn` pass on the Claude side (this repo does
not carry its own `learn` port — see `pipeline-state/HANDOFF-CONTRACT.md`
§ Observation tagging).

### 3. Act on Findings

- **No CRITICAL/HIGH/MEDIUM findings**: the diff is APPROVE — proceed to
  the next step (verify/ship/handoff).
- **Any CRITICAL/HIGH/MEDIUM findings**: fix them yourself, in this same
  session, before proceeding. Re-run the checklist against the updated
  diff. There is no "spawn someone else to fix it" step — you are the
  only engineer on shift.

## Review Checklist

Shape measurements are enforced by build hooks. Only flag a measurement
if it EXCEEDS limits despite the hooks — that indicates a hook gap, and
the finding severity is "process" (fix the hook, not just the code).

- [ ] Shape constraints met (AGENTS.md § Code Shape Rules)
- [ ] No DRY violations (duplicated logic)
- [ ] SRP: each class/module has one reason to change
- [ ] Tests are meaningful (not just coverage padding)
- [ ] No TODO/FIXME without linked ticket
- [ ] Error handling follows guard clause pattern
- [ ] No hardcoded values (extract to constants)

## Severity Grading

| Severity | Definition | Examples | Blocks? |
|----------|-----------|----------|---------|
| CRITICAL | Security vulnerability or data loss risk | SQL injection, exposed secrets, auth bypass | Yes |
| HIGH | Correctness bug or significant design flaw | Missing error handling, broken invariant, SOLID violation | Yes |
| MEDIUM | Code quality issue causing maintenance pain | DRY violation across files, unclear naming, missing edge case test, unnecessary coupling | Yes |
| LOW | Minor improvement or style preference | Variable rename suggestion, comment improvement | No |
| INFO | Observation, context, or positive feedback | "Nice pattern," "FYI this also handles X" | No |

**Verdict rule:** APPROVE if no CRITICAL, HIGH, or MEDIUM findings.
CHANGES_REQUESTED (fix-it-yourself) if any exist. LOW and INFO are noted
but do not block.

**In-cycle enforcement:** CHANGES_REQUESTED findings are fixed in this
same session, never deferred to a follow-up ticket or shipped
known-broken. If a finding is genuinely orthogonal (different module,
different contract, different user journey), mark it INFO, not MEDIUM.

## Preventability Classification (Backward Feedback)

For each finding, classify whether it could have been prevented at
write-time:

| Classification | Criteria | Example |
|---|---|---|
| **Preventable** | Standard pattern violation the build step should have caught | Missing input validation, SOLID violation, naming issue |
| **Review-level** | Requires cross-cutting perspective a fresh read surfaces | Architectural concern, subtle race condition, design inconsistency |

Tag each finding with `preventable: true/false`. The Claude side's
`/harness:learn` uses this to create instincts that prevent the same
findings earlier next time.

## Phase Output

```
Verdict: APPROVE / CHANGES_REQUESTED
Next: If APPROVE → proceed (verify/ship/handoff)
      If CHANGES_REQUESTED → fix in this session, re-run this checklist
Findings: [list of specific findings with severity and preventability]
```

### Context for Next Step

Record a `## Context for Fix/Verify` note (in `HANDOFF.md` or the
pipeline-state file, whichever applies) so the next reader — you in a
later session, or Claude on the next shift — has this:

```markdown
## Context for Fix/Verify
- **Finding context**: [for each finding: not just "fix X" but "fix X because Y, consider approach Z"]
- **Areas of strength**: [what the diff did well — reinforces good patterns]
```
