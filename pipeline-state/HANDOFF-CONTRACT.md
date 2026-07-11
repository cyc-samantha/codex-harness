# Contractor Handoff Contract (CX-71, CX-73)

Codex is a fallback **contractor**: it picks up work when the Claude
harness's 5-hour usage window runs out, and hands work back when Claude
comes back on shift. Claude is primary. This contract exists because both
harnesses share one runtime-state root (`HARNESS_DATA`, see AGENTS.md §
Runtime Model) — there is exactly one copy of `pipeline-state/`,
`session-memory/`, and the learning observations log, never two synced
copies. `HANDOFF.md` and `ACTIVE_HARNESS` are the coordination surface on
top of that shared root; they do not replace it.

The Claude-side counterpart skill is `/handoff` in the `.claude` harness
repo (separate repo, added in parallel). **Keep the two schema copies in
sync** — this file and the Claude-side `HANDOFF.md` schema doc must not
diverge.

## `HANDOFF.md` contract v1

Path: `$HARNESS_DATA/pipeline-state/{task-id}/HANDOFF.md`

```markdown
---
handoff_version: 1
task_id: <task-id>
handoff_from: claude | codex
handoff_at: <ISO 8601>
branch: <feature branch or null>
worktree: <absolute path or null>
phase: <pipeline phase, or ad-hoc>
tests_state: passing | failing | not-run
baton: codex | claude
---

## Done (verified)
## In Flight
## Next Actions
## Landmines
```

### Frontmatter fields

- `handoff_version` — schema version of this file, always `1` for this
  contract revision. Bump on breaking change to the field set or section
  list; readers should refuse (or warn loudly) on an unrecognized version
  rather than guess.
- `task_id` — matches the `pipeline-state/{task-id}/` directory this
  `HANDOFF.md` lives under; must agree with `pipeline.md`'s `task_id` in
  the same directory.
- `handoff_from` — which harness wrote this file (`claude` or `codex`).
  Identifies the author, not the recipient.
- `handoff_at` — ISO 8601 timestamp of when this file was written. Used to
  pick the newest `HANDOFF.md` when several exist for the same task.
- `branch` — the feature branch the handed-off work lives on, or `null`
  if no branch exists yet (e.g. still in Plan phase).
- `worktree` — absolute path to the worktree the work was done in, or
  `null` if none was created. The recipient harness creates its own
  worktree under its own convention; this path is a pointer for
  reconciliation, not something the recipient is obligated to reuse.
- `phase` — the pipeline phase in flight at handoff time (e.g. `build`,
  `security-review`), or the literal string `ad-hoc` if the work was not
  running under the structured pipeline.
- `tests_state` — `passing`, `failing`, or `not-run`, as of `handoff_at`.
  This is a claim, not a guarantee — see Reconciliation Rule below.
- `baton` — which harness should pick up next (`codex` or `claude`). This
  is the value the `ACTIVE_HARNESS` baton file should be flipped to as
  part of the same handoff.

### Body sections

- **Done (verified)** — work items completed with verification evidence
  (test output, command run, file diff) cited inline. Do not list
  "done" work without the evidence that proves it — an unverified claim
  belongs in "In Flight," not here.
- **In Flight** — work started but not complete: partial diffs, a slice
  mid-RED, a hypothesis being tested. State exactly where it was
  interrupted.
- **Next Actions** — an ordered, numbered list. Each entry must be
  resumable by a cold reader with no other context: what to do, which
  file/AC it targets, and what "done" looks like for that entry.
- **Landmines** — known traps for the next harness: flaky tests, a
  half-applied migration, a dependency that needs a specific install
  order, anything that would cost the picker-upper time to rediscover.

### Rules

- `HANDOFF.md` is **additive prose context**, not the source of truth.
  `pipeline-state/{task-id}/pipeline.md` remains the machine-readable
  truth for phase/verdict state.
- Whoever picks up a `HANDOFF.md` **MUST reconcile it against git ground
  truth before trusting it** — confirm the branch exists, the worktree
  exists (or re-create it), and re-run the test command to confirm
  `tests_state`. On any conflict between the prose and git/test reality,
  git and test reality win.

## Baton file (`ACTIVE_HARNESS`)

Path: `$HARNESS_DATA/ACTIVE_HARNESS`

Single line, space-separated:

```
<claude|codex> <ISO 8601>
```

Example: `codex 2026-07-11T18:04:00Z`

The baton names which harness is currently on shift and when it last took
the baton. Session-start on either side reads this file and warns if the
*other* side currently holds the baton — this is the guard against two
harnesses writing `pipeline-state/` concurrently. It is advisory (a warn,
not a hard block): a stale baton from a crashed session must not
permanently lock the other harness out.

## Observation tagging (`source: codex`)

Every observation record the Codex side appends to the shared learning
observations JSONL (`$HARNESS_DATA/learning/observations/*.jsonl`, same
format as the Claude harness's Iron Law 7 capture) gets an extra field:

```json
{"source": "codex", ...}
```

Claude-authored observation records may omit `source` entirely — the
Claude harness's `/harness:learn` (and this repo's `harness-learn` port)
treats a missing `source` field as `claude` by default. This lets the
`/harness:learn` segmentation step weight or filter instincts by
authoring harness (e.g. down-weight a pattern that only ever fired under
Codex's tool surface before promoting it as a cross-harness instinct).

Enforcement of this tag is a **skill procedure**, not a schema validator:
`harness-resume-handoff` (see `.agents/skills/harness-resume-handoff/`)
Step 5 appends `"source": "codex"` to every observation it writes. There
is no separate CX-73 artifact beyond this documented contract plus that
skill step.
