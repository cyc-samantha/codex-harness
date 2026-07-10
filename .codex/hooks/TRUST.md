# Hook Trust — one-time step on every fresh clone (CX-04)

Codex CLI requires reviewing and trusting non-managed `command`-type hooks
before it will run them. Unlike the Claude harness — whose hooks are
implicitly trusted by living under `~/.claude/hooks/`, a directory the user
already controls — a fresh `codex-harness` checkout ships hooks *inside the
repo* (`.codex/hooks/hooks.json`), and Codex treats them as untrusted until
you approve them.

## The flow on a fresh clone

1. Clone the repo and start `codex` at the repo root.
2. Run `/hooks` in the CLI. Codex lists every hook registered from
   `.codex/hooks/hooks.json` with its event (`PreToolUse`, `PostToolUse`,
   `SessionStart`, ...) and the command it executes.
3. **Read every script before trusting it.** Each entry points at a shell
   script in this directory (`.codex/hooks/*.sh`). Open it. This is the only
   review standing between you and an unreviewed script executing on every
   tool call.
4. Trust the reviewed entries. Until you do, the enforcement layer (shape
   rules, main-branch guard, observation capture) is silently inert — the
   harness degrades to advisory-only without telling you.

## Why this file exists

This is a genuine UX regression versus the Claude harness (PLAN.md §7):
there, hook trust is implicit; here it is a manual gate per clone. The
regression is intentional on Codex's side (supply-chain caution — repo
hooks are third-party code from the CLI's point of view) and mirrors the
same caution this harness itself recommends for `AGENTS.override.md` files
in unfamiliar repos.

## Verification

After trusting, confirm hooks actually fire: from the repo root, attempt a
bare `git checkout -b test-branch` inside a harness session once CX-50 has
landed — the main-branch guard must block it. If it does not, hooks are not
trusted (or not registered) and NO pipeline work should proceed: a gate that
cannot evaluate fails closed (Iron Law 8).

<!-- Registered hooks land here in Phase 5 (CX-50, CX-51, CX-53) along with
     hooks.json itself. This file is deliberately authored first so the
     trust procedure exists before the first hook does. -->
