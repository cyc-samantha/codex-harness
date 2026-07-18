# Builder–Guardian workflow

The Builder–Guardian coordinator turns a JSON Task Contract into an auditable,
commit-bound delivery decision. Runtime evidence defaults to
`${HARNESS_DATA:-$HOME/.claude}/pipeline-state/<task-id>` and is never selected
by "latest file" lookup.

## State flow

```text
CONTRACT_READY -> BUILDING -> AWAITING_REVIEW
                                  |       |
                     CHANGES_REQUESTED   GUARDIAN_APPROVED
                                  |       |
                             BUILDING   VERIFYING
                                          |
                              VERIFICATION_FAILED | VERIFIED
                                          |           |
                                       BUILDING   READY_TO_SHIP
```

`BLOCKED`, `CONTRACT_CHANGE_REQUIRED`, and `REVISION_LIMIT_REACHED` fail
closed. A changed target always requires a new ephemeral Guardian session.

## Task Contract

Create a JSON document containing `task_id`, `objective`, measurable
`acceptance_criteria`, `constraints`, `allowed_scope`, `prohibited_changes`,
`builder_checks`, `final_checks`, `expected_deliverables`, `risks`,
`repository`, and `base_commit`. Each acceptance criterion needs an ID,
statement, and at least one typed verification method with concrete evidence.

Allowed verification kinds are `test`, `build`, `typecheck`, `lint`, `static`,
`inspection`, and `manual`. Scope entries are shell-style path patterns.
Contracts are copied into task state and SHA-256 bound; changing the copy stops
the run with `CONTRACT_CHANGE_REQUIRED`.

## Commands

```bash
scripts/codex-harness init task-contract.json
scripts/codex-harness build <task-id>
scripts/codex-harness review <task-id>
scripts/codex-harness verify <task-id>
scripts/codex-harness gate <task-id>
```

`build` creates a dedicated branch/worktree and launches an ephemeral Builder
with `workspace-write`. A caller that already manages the Builder can instead
submit a conforming package with `handoff <task-id> <package.json>`.

`review` launches a separate ephemeral Guardian with a `read-only` sandbox. It
receives only the Task Contract, repository instructions available in the
checkout, immutable target, changed-file handoff, and test evidence. The
coordinator fingerprints the repository before and after review and blocks any
write attempt.

`verify` is admitted only by `APPROVED`. It checks clean HEAD identity, exports
the exact approved commit into a disposable checkout, and executes every final
command there. Failed, missing, timed-out, or mismatched evidence cannot ship.

`gate` is the only command that emits `READY_TO_SHIP`. It rebinds the Guardian
verdict and verification evidence to task, repository, run, worktree, and SHA,
then writes `ready.json`.

## Authority boundaries

| Role | Repository permission | Output authority |
|---|---|---|
| Builder | Dedicated worktree, workspace-write | Builder handoff only |
| Guardian | Read-only sandbox plus mutation fingerprint | Structured verdict only |
| Verifier | Disposable exported checkout | Deterministic pass/fail only |
| Coordinator | Runtime state and worktree lifecycle | State transitions and ready gate |

There is no implicit override. Any future override feature must record the
authorising person, explicit action, failed gate, reason, and timestamp in the
append-only transition log.

## Guardian verdict

Every AC receives `PASS`, `FAIL`, `NOT_PROVEN`, or justified
`NOT_APPLICABLE`. `NOT_PROVEN` blocks approval. Blocking findings carry an ID,
severity, component, description, violated requirement, expected resolution,
and supporting evidence. The top-level verdict is exactly `APPROVED`,
`CHANGES_REQUESTED`, or `BLOCKED`.
