---
name: "polish"
description: "Use when user wants to Lightweight mechanical cleanup pass between Build and Review."
context: fork
model: haiku
---

# Polish

## What This Skill Does

A fast, cheap cleanup pass that runs after Build, before the code-review /
security-review self-review passes. Fixes only mechanical issues —
naming, dead code, import ordering, commented-out blocks, unused
variables. Does NOT touch design, architecture, or logic.

The original insight (self-review is author-biased) still applies, but a
single-thread contractor has no separate agent to hand this to for fresh
eyes. Compensate by treating this as a genuinely SEPARATE pass: re-read
the diff top-to-bottom as if you had not written it, looking ONLY for the
mechanical issues below — do not re-litigate design decisions here, that
is `$harness-code-review`'s job.

## When to Run

- After the build/fix work is functionally complete, before
  `$harness-code-review` / `$harness-security-review`.
- Skip for genuinely trivial diffs (a handful of lines with nothing to
  mechanically clean up) — this pass earns its keep on non-trivial diffs.

## Process

### 1. Read Changed Files

```bash
git diff --name-only main...HEAD
```

Read each changed source file (skip tests, configs, lock files).

### 2. Fix Mechanical Issues Only

For each file, check and fix:
- **Dead imports**: imported but never used
- **Commented-out code**: remove (git has history)
- **Unused variables**: declared but never referenced
- **Import ordering**: group by stdlib, external, internal
- **Naming clarity**: single-letter variables (except loop counters), abbreviations, misleading names
- **Inconsistent formatting**: mixed quote styles, trailing whitespace, inconsistent semicolons

For comments, **FLAG but do NOT auto-delete**:
- Explanatory WHAT comments (comments that restate what the code does) — report these in the output as code-clarity smells; the code, not the comment, needs improving
- Changelog/apology comments ("fixed by X", "temporary hack")

**NEVER touch**:
- Doc-comments (`/** */`, `///`, `"""…"""`), license/copyright headers — preserve exactly
- `# WHY:` / `# SAFETY:` / `# NOTE:` prefixed comments — these are legitimate WHY notes
- Any comment you cannot confidently classify as a WHAT restatement

### 3. Do NOT Touch

- Design decisions or architecture
- Logic or control flow
- Test structure or assertions
- Any behavioral change whatsoever

If unsure whether a change is mechanical or behavioral, skip it.

### 4. Commit and Report

```bash
git add [specific files]
git commit -m "chore: polish — mechanical cleanup"
```

Report:
```
Polished N files:
- file.ts: removed 2 dead imports, fixed variable name
- other.ts: removed commented-out code block
```

## Phase Output

```
Verdict: POLISHED / NO_CHANGES_NEEDED
Next: run $harness-code-review and $harness-security-review yourself (inline self-review, either order)
Artifacts: [list of files cleaned, changes per file]
```
