# Pipeline State (`pipeline-state/{task-id}/*.md`)

Per-task phase files — YAML frontmatter + Summary / Test Results / Key
Findings / Next Phase Input sections — kept byte-for-byte identical to the
Claude harness's contract. A task started under one harness can be resumed
under the other when both point their runtime-state root at the same
directory (PLAN.md §3, portable verbatim).

Everything in this directory except this README is runtime state and is
gitignored (see repo-root `.gitignore`) — only the contract lives in the
repo, never the state itself.
