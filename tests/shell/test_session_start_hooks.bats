#!/usr/bin/env bats
# CX-53 — SessionStart maintenance hooks (worktree-reaper, learning-gc,
# codebase-map-rebuild stub). These are maintenance, not blocking gates:
# they always exit 0 and never stop work.

load helper

setup() {
  REAPER="${HOOKS_DIR}/worktree-reaper.sh"
  LEARNGC="${HOOKS_DIR}/learning-gc.sh"
  CBMAP="${HOOKS_DIR}/codebase-map-rebuild.sh"
  export HARNESS_DATA="${BATS_TEST_TMPDIR}/data"
  export CLAUDE_WORKTREE_REAPER_INTERVAL_HOURS=0
}

@test "worktree-reaper reaps a merged, clean, non-ahead worktree" {
  make_repo
  local wt="$REPO_DIR/.claude/worktrees/done"
  git -C "$REPO_DIR" worktree add -q -b feat/done "$wt"
  run bash -c "cd '$REPO_DIR' && '$REAPER'"
  [ "$status" -eq 0 ]
  [ ! -d "$wt" ]
}

@test "worktree-reaper retains a dirty worktree" {
  make_repo
  local wt="$REPO_DIR/.claude/worktrees/dirty"
  git -C "$REPO_DIR" worktree add -q -b feat/dirty "$wt"
  echo change > "$wt/seed"
  run bash -c "cd '$REPO_DIR' && '$REAPER'"
  [ "$status" -eq 0 ]
  [ -d "$wt" ]
}

@test "worktree-reaper honours its bypass gate" {
  make_repo
  local wt="$REPO_DIR/.claude/worktrees/done"
  git -C "$REPO_DIR" worktree add -q -b feat/done "$wt"
  run bash -c "cd '$REPO_DIR' && CLAUDE_DISABLE_WORKTREE_REAPER=1 '$REAPER'"
  [ "$status" -eq 0 ]
  [ -d "$wt" ]
}

@test "learning-gc honours its bypass gate" {
  run bash -c "CLAUDE_DISABLE_LEARNING_GC=1 '$LEARNGC'"
  [ "$status" -eq 0 ]
}

@test "learning-gc exits 0 when no shared-root runner is present" {
  export HARNESS_ROOT="${BATS_TEST_TMPDIR}/empty-root"
  mkdir -p "$HARNESS_ROOT"
  run bash -c "HARNESS_ROOT='$HARNESS_ROOT' '$LEARNGC'"
  [ "$status" -eq 0 ]
}

@test "learning-gc delegates to the shared-root runner when present" {
  export HARNESS_ROOT="${BATS_TEST_TMPDIR}/root"
  mkdir -p "$HARNESS_ROOT/hooks"
  local marker="${BATS_TEST_TMPDIR}/gc-ran"
  printf '#!/usr/bin/env bash\ntouch "%s"\n' "$marker" > "$HARNESS_ROOT/hooks/learning-gc.sh"
  chmod +x "$HARNESS_ROOT/hooks/learning-gc.sh"
  run bash -c "HARNESS_ROOT='$HARNESS_ROOT' '$LEARNGC'"
  [ "$status" -eq 0 ]
  [ -f "$marker" ]
}

@test "codebase-map-rebuild stub exits 0" {
  run bash -c "'$CBMAP'"
  [ "$status" -eq 0 ]
}

teardown() { cxh_cleanup; }
