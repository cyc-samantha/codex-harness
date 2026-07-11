---
name: "resume-handoff"
description: "Resume work handed off by the Claude harness: reads ACTIVE_HARNESS baton + HANDOFF.md, reconciles against git ground truth, continues the task vertically, and wraps by writing a return HANDOFF.md with baton: claude."
argument-hint: "Optional: task ID to resume (auto-detects newest baton: codex HANDOFF.md if only one)"
---

# Resume Handoff (contractor pickup)

## What This Skill Does

Picks up work the Claude harness handed off when its 5-hour usage window
ran out. Reads the shared-root `ACTIVE_HARNESS` baton and the newest
`baton: codex` `HANDOFF.md`, reconciles the prose against git ground
truth, continues the `Next Actions` vertically (Codex has no subagents —
this is single-thread, not a dispatch), and hands the work back to Claude
by writing a return `HANDOFF.md` and flipping the baton.

The schema for `HANDOFF.md` and `ACTIVE_HARNESS` is defined once, in
`pipeline-state/HANDOFF-CONTRACT.md` — read it before using this skill if
either file's shape is unfamiliar. The Claude-side counterpart is the
`/handoff` skill in the `.claude` harness repo.

## When to Invoke

- At session start, after checking `$HARNESS_DATA/ACTIVE_HARNESS` and
  finding the baton set to `codex`.
- When the user asks Codex to "pick up where Claude left off" or
  similar.

## Process

### Step 1: Check the baton

```bash
HARNESS_DATA="${HARNESS_DATA:-$HOME/.claude}"
cat "$HARNESS_DATA/ACTIVE_HARNESS" 2>/dev/null
```

If the file is missing, or its first field is not `codex`, **stop and
report** — Claude is on shift (or no handoff has occurred). Do not read
or write any `HANDOFF.md` in this state: writing `pipeline-state/`
concurrently with an active Claude session is exactly what the baton
exists to prevent.

### Step 2: Find handed-off work

```bash
find "$HARNESS_DATA/pipeline-state" -maxdepth 2 -mindepth 2 -name "HANDOFF.md" \
  -exec grep -l "^baton: codex$" {} \;
```

List every match. If more than one, the file with the newest
`handoff_at` timestamp wins as the primary pickup; still report the
others by task ID so the user can redirect if the auto-picked one is
wrong.

If none are found while the baton reads `codex`, that is a legitimate
but unusual state (baton flipped ad-hoc, not via a `HANDOFF.md`-bearing
handoff) — report `NOTHING_TO_RESUME` rather than guessing at a task.

### Step 3: Reconcile against git ground truth

Trust git and the test suite over the `HANDOFF.md` prose on any
conflict:

```bash
git -C "$WORKTREE" status --porcelain   # worktree still exists?
git -C "$WORKTREE" branch --show-current  # matches HANDOFF.md `branch`?
# run the project's test command; compare the result against `tests_state`
```

If the worktree path from `HANDOFF.md` no longer exists, re-create it
from the named `branch` per the Worktree + Commit Protocol in
`AGENTS.md`. If the branch itself is gone, report `STATE_DIVERGED` and
stop — do not silently reconstruct lost work from prose alone.

### Step 4: Continue vertically

Work the `Next Actions` list in order. Codex has no subagent/worktree
dispatch equivalent to the Claude harness's parallel-subagent default —
every step here runs in this single session, following the same
discipline `AGENTS.md` requires elsewhere: TDD (RED before GREEN), the
code shape rules, WIP commits at natural checkpoints, no `git add -A`.

Cross-reference the `Landmines` section before touching anything it
warns about.

### Step 5: Capture observations

Append any pipeline observations to the shared learning observations
JSONL with the `source` field set, per `pipeline-state/HANDOFF-CONTRACT.md`
§ Observation tagging:

```json
{"source": "codex", ...}
```

### Step 6: Wrap and hand back

Before session end, or once the `Next Actions` list is exhausted:

1. Write a return `HANDOFF.md` at the same
   `$HARNESS_DATA/pipeline-state/{task-id}/HANDOFF.md` path with
   `handoff_from: codex`, `baton: claude`, and fresh `Done (verified)` /
   `In Flight` / `Next Actions` / `Landmines` sections describing the
   state as Codex leaves it.
2. WIP-commit and push the branch (`git push -u origin <branch>` from the
   worktree — never from repo-root `main`).
3. Flip the baton:
   ```bash
   echo "claude $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$HARNESS_DATA/ACTIVE_HARNESS"
   ```

The Claude harness's SessionStart pipeline check (see the global
CLAUDE.md § Session Start) picks up the returned `HANDOFF.md`
automatically on its next session.

## Phase Output

```
Verdict: RESUMED / NO_BATON / NOTHING_TO_RESUME / STATE_DIVERGED
Next: [what the picked-up task needs next, or why resume was refused]
Artifacts: [HANDOFF.md path, task ID, branch, worktree path]
```
$ARGUMENTS
