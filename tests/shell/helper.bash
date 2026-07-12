# Shared bats helpers for the .codex/hooks test suite.
# WHY: every hook reads a JSON tool payload on stdin and signals a block with
# exit 2; these helpers build payloads and disposable git repos so each test
# drives a hook exactly as Codex would, without a live Codex session.

HOOKS_DIR="${BATS_TEST_DIRNAME}/../../.codex/hooks"

# payload_bash <command> — emit a PreToolUse Bash tool payload.
payload_bash() {
  jq -nc --arg cmd "$1" '{tool_name:"Bash",tool_input:{command:$cmd}}'
}

# payload_write <file_path> — emit a PostToolUse Write tool payload.
payload_write() {
  jq -nc --arg fp "$1" '{tool_name:"Write",tool_input:{file_path:$fp}}'
}

# WHY: temp paths must NOT contain the token "/test/" — the shape hooks skip any
# file under a test directory, and BATS_TEST_TMPDIR embeds ".../test/N/...". Use
# a neutral base so hook path-filters see the fixture as ordinary source.
cxh_mktemp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/cxh.XXXXXX"
}

cxh_init_repo() {
  local dir="$1"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email t@t.t
  git -C "$dir" config user.name t
  : > "$dir/seed"
  git -C "$dir" add seed
  git -C "$dir" commit -qm seed
}

# make_repo — create a temp git repo with one commit. Exports REPO_DIR.
make_repo() {
  REPO_DIR="$(cxh_mktemp_dir)"
  cxh_init_repo "$REPO_DIR"
  export REPO_DIR
}

# make_repo_with_worktree — create a temp git repo plus one registered
# worktree. Exports REPO_DIR and WORKTREE_DIR for the calling test.
make_repo_with_worktree() {
  make_repo
  WORKTREE_DIR="$(cxh_mktemp_dir)"
  rmdir "$WORKTREE_DIR"
  git -C "$REPO_DIR" worktree add -q -b feat/x "$WORKTREE_DIR"
  export WORKTREE_DIR
}

# cxh_cleanup — remove fixtures created by make_repo*. Safe to call in teardown.
cxh_cleanup() {
  [[ -n "${WORKTREE_DIR:-}" ]] && rm -rf "$WORKTREE_DIR"
  [[ -n "${REPO_DIR:-}" ]] && rm -rf "$REPO_DIR"
  return 0
}
