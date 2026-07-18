#!/usr/bin/env bats

load helper

setup() {
  make_repo
  STATE_ROOT="$(cxh_mktemp_dir)"
  HARNESS="${BATS_TEST_DIRNAME}/../../scripts/codex-harness"
  CONTRACT="$STATE_ROOT/contract.json"
  HEAD_SHA="$(git -C "$REPO_DIR" rev-parse HEAD)"
  make_contract
}

teardown() {
  cxh_cleanup
  [[ -n "${STATE_ROOT:-}" ]] && rm -rf "$STATE_ROOT"
}

make_contract() {
  jq -n --arg repo "$REPO_DIR" --arg sha "$HEAD_SHA" '{
    task_id:"BG-1", objective:"prove workflow", constraints:[], allowed_scope:["seed","tests/**"],
    prohibited_changes:["protected branches"], repository:$repo, base_commit:$sha,
    acceptance_criteria:[{id:"AC-1",statement:"evidence is bound",verification:[{kind:"test",evidence:"exit zero"}]}],
    builder_checks:[{name:"unit",command:"true"}], final_checks:[{name:"unit",command:"true",timeout_seconds:5}],
    expected_deliverables:["seed"], risks:["stale evidence"], max_review_cycles:2
  }' > "$CONTRACT"
}

init_task() {
  run "$HARNESS" --state-root "$STATE_ROOT" init "$CONTRACT"
  [ "$status" -eq 0 ]
}

make_handoff() {
  jq -n --arg repo "$REPO_DIR" --arg sha "$HEAD_SHA" '{
    task_id:"BG-1",review_target:$sha,base_commit:$sha,changed_files:[],summary:"done",
    ac_evidence:{"AC-1":"test"},tests_changed:["tests/unit"],commands:["true"],
    results:[{command:"true",passed:true}],limitations:[],risks:[],builder_session_id:"builder-1",
    worktree:$repo,branch:"feat/test",repository:$repo
  }' > "$STATE_ROOT/handoff-input.json"
}

submit_handoff() {
  make_handoff
  run "$HARNESS" --state-root "$STATE_ROOT" handoff BG-1 "$STATE_ROOT/handoff-input.json"
  [ "$status" -eq 0 ]
}

make_fake_codex() {
  FAKE_CODEX="$STATE_ROOT/fake-codex"
  cat > "$FAKE_CODEX" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output=""
cwd=""
prompt="${*: -1}"
while (($#)); do
  [[ "$1" == "--output-last-message" ]] && { output="$2"; shift 2; continue; }
  [[ "$1" == "--cd" ]] && { cwd="$2"; shift 2; continue; }
  shift
done
cd "$cwd"
task="$(sed -n 's#Task Contract: .*/\([^/]*\)/contract.json#\1#p' <<< "$prompt")"
target="$(sed -n 's/^Fixed review target: //p' <<< "$prompt")"
session="$(sed -n 's/^Guardian session ID: //p' <<< "$prompt")"
repo="$(sed -n 's/^Repository identity: //p' <<< "$prompt")"
worktree="$(sed -n 's/^Worktree identity: //p' <<< "$prompt")"
run_id="$(sed -n 's/^Pipeline run ID: //p' <<< "$prompt")"
jq -n --arg task "$task" --arg target "$target" --arg session "$session" --arg repo "$repo" --arg worktree "$worktree" --arg run "$run_id" '{verdict:"APPROVED",task_id:$task,reviewed_target:$target,guardian_session_id:$session,repository:$repo,worktree:$worktree,run_id:$run,ac_results:[{id:"AC-1",result:"PASS",justification:"test evidence"}],blocking_findings:[],non_blocking_findings:[],missing_evidence:[],commands:["inspection"],timestamp:"2026-07-18T00:00:00Z"}' > "$output"
SH
  chmod +x "$FAKE_CODEX"
  export CODEX_BIN="$FAKE_CODEX"
}

approve() {
  make_fake_codex
  run "$HARNESS" --state-root "$STATE_ROOT" review BG-1
  [ "$status" -eq 0 ]
}

@test "invalid or unverifiable Task Contracts fail closed" {
  jq 'del(.objective)' "$CONTRACT" > "$CONTRACT.bad"
  run "$HARNESS" --state-root "$STATE_ROOT" init "$CONTRACT.bad"
  [ "$status" -eq 2 ]
  [[ "$output" == *INVALID_TASK_CONTRACT* ]]

  jq '.acceptance_criteria[0].verification=[]' "$CONTRACT" > "$CONTRACT.bad"
  run "$HARNESS" --state-root "$STATE_ROOT" init "$CONTRACT.bad"
  [ "$status" -eq 2 ]

  jq '.task_id="../escape"' "$CONTRACT" > "$CONTRACT.bad"
  run "$HARNESS" --state-root "$STATE_ROOT" init "$CONTRACT.bad"
  [ "$status" -eq 2 ]
}

@test "the immutable contract and Builder handoff enforce identity scope tests and checks" {
  init_task
  jq '.objective="changed"' "$STATE_ROOT/BG-1/contract.json" > "$STATE_ROOT/changed"
  mv "$STATE_ROOT/changed" "$STATE_ROOT/BG-1/contract.json"
  run "$HARNESS" --state-root "$STATE_ROOT" status BG-1
  [ "$status" -eq 2 ]
  [[ "$output" == *CONTRACT_CHANGE_REQUIRED* ]]

  cp "$CONTRACT" "$STATE_ROOT/BG-1/contract.json"
  make_handoff
  jq '.changed_files=["forbidden"]' "$STATE_ROOT/handoff-input.json" > "$STATE_ROOT/bad"
  run "$HARNESS" --state-root "$STATE_ROOT" handoff BG-1 "$STATE_ROOT/bad"
  [ "$status" -eq 2 ]
}

@test "Builder runs in a dedicated workspace-write worktree and emits only a handoff" {
  init_task
  FAKE_BUILDER="$STATE_ROOT/fake-builder"
  cat > "$FAKE_BUILDER" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${BUILDER_ARGS_LOG}"
output=""
cwd=""
while (($#)); do
  [[ "$1" == "--output-last-message" ]] && { output="$2"; shift 2; continue; }
  [[ "$1" == "--cd" ]] && { cwd="$2"; shift 2; continue; }
  shift
done
echo built >> "$cwd/seed"
git -C "$cwd" add seed
git -C "$cwd" commit -qm build
target="$(git -C "$cwd" rev-parse HEAD)"
base="$(git -C "$cwd" rev-parse HEAD^)"
jq -n --arg target "$target" --arg base "$base" '{review_target:$target,base_commit:$base,changed_files:["seed"],summary:"built",ac_evidence:{"AC-1":"test"},tests_changed:["tests/unit"],commands:["true"],results:[{command:"true",passed:true}],limitations:[],risks:[]}' > "$output"
SH
  chmod +x "$FAKE_BUILDER"
  export CODEX_BIN="$FAKE_BUILDER"
  export BUILDER_ARGS_LOG="$STATE_ROOT/builder-args"
  run "$HARNESS" --state-root "$STATE_ROOT" build BG-1
  [ "$status" -eq 0 ]
  [ "$(jq -r .status <<< "$output")" = AWAITING_REVIEW ]
  grep -q -- '--sandbox workspace-write' "$BUILDER_ARGS_LOG"
  [[ "$(jq -r .worktree "$STATE_ROOT/BG-1/handoff.json")" == *builder-BG-1 ]]
}

@test "Guardian runs in fresh ephemeral read-only context and approval is commit-bound" {
  init_task
  submit_handoff
  make_fake_codex
  run "$HARNESS" --state-root "$STATE_ROOT" review BG-1
  [ "$status" -eq 0 ]
  [ "$(jq -r .status <<< "$output")" = GUARDIAN_APPROVED ]
  [ "$(jq -r .reviewed_target "$STATE_ROOT/BG-1/guardian-verdict.json")" = "$HEAD_SHA" ]
}

@test "Guardian write attempts are detected and block the workflow" {
  init_task
  submit_handoff
  make_fake_codex
  sed -i '/cd "$cwd"/a echo mutation >> "$PWD/guardian-write"' "$FAKE_CODEX"
  run "$HARNESS" --state-root "$STATE_ROOT" review BG-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"write protection"* ]]
  [ "$(jq -r .status "$STATE_ROOT/BG-1/state.json")" = BLOCKED ]
}

@test "CHANGES_REQUESTED returns to Builder and consumes a review cycle" {
  init_task
  submit_handoff
  make_fake_codex
  sed -i 's/verdict:"APPROVED"/verdict:"CHANGES_REQUESTED"/' "$FAKE_CODEX"
  sed -i 's/ac_results:\[{id:"AC-1",result:"PASS"/ac_results:[{id:"AC-1",result:"FAIL"/' "$FAKE_CODEX"
  run "$HARNESS" --state-root "$STATE_ROOT" review BG-1
  [ "$status" -eq 0 ]
  [ "$(jq -r .status <<< "$output")" = BUILDING ]
  [ "$(jq -r .review_cycle <<< "$output")" -eq 1 ]
}

@test "verification cannot precede approval or run against dirty or changed HEAD" {
  init_task
  submit_handoff
  run "$HARNESS" --state-root "$STATE_ROOT" verify BG-1
  [ "$status" -eq 2 ]
  approve
  echo dirty > "$REPO_DIR/dirty"
  run "$HARNESS" --state-root "$STATE_ROOT" verify BG-1
  [ "$status" -eq 2 ]
  [[ "$output" == *VERIFICATION_BLOCKED* ]]
}

@test "happy path emits identity-bound READY_TO_SHIP and audit transitions" {
  init_task
  submit_handoff
  approve
  run "$HARNESS" --state-root "$STATE_ROOT" verify BG-1
  [ "$status" -eq 0 ]
  [ "$(jq -r .status <<< "$output")" = VERIFIED ]
  run "$HARNESS" --state-root "$STATE_ROOT" gate BG-1
  [ "$status" -eq 0 ]
  [ "$(jq -r .status <<< "$output")" = READY_TO_SHIP ]
  [ "$(jq -r .approved_commit <<< "$output")" = "$HEAD_SHA" ]
  [ "$(jq -r .guardian_verdict <<< "$output")" = APPROVED ]
  [ "$(wc -l < "$STATE_ROOT/BG-1/transitions.jsonl")" -ge 6 ]
}

@test "verification failure fails closed and invalidates approval" {
  jq '.final_checks=[{name:"failure",command:"false",timeout_seconds:5}]' "$CONTRACT" > "$CONTRACT.tmp"
  mv "$CONTRACT.tmp" "$CONTRACT"
  init_task
  submit_handoff
  approve
  run "$HARNESS" --state-root "$STATE_ROOT" verify BG-1
  [ "$status" -eq 2 ]
  [[ "$output" == *VERIFICATION_FAILED* ]]
  [ "$(jq -r .status "$STATE_ROOT/BG-1/state.json")" = BUILDING ]
  run "$HARNESS" --state-root "$STATE_ROOT" gate BG-1
  [ "$status" -eq 2 ]
}

@test "stale task evidence and a post-verification dirty worktree cannot ship" {
  init_task
  submit_handoff
  approve
  run "$HARNESS" --state-root "$STATE_ROOT" verify BG-1
  [ "$status" -eq 0 ]
  jq '.task_id="OTHER"' "$STATE_ROOT/BG-1/verification.json" > "$STATE_ROOT/stale"
  mv "$STATE_ROOT/stale" "$STATE_ROOT/BG-1/verification.json"
  run "$HARNESS" --state-root "$STATE_ROOT" gate BG-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"stale evidence"* ]]
}

@test "verification timeout is recorded and fails closed" {
  jq '.final_checks=[{name:"timeout",command:"sleep 2",timeout_seconds:1}]' "$CONTRACT" > "$CONTRACT.tmp"
  mv "$CONTRACT.tmp" "$CONTRACT"
  init_task
  submit_handoff
  approve
  run "$HARNESS" --state-root "$STATE_ROOT" verify BG-1
  [ "$status" -eq 2 ]
  [ "$(jq -r '.commands[0].output' "$STATE_ROOT/BG-1/verification.json")" = timeout ]
  [ "$(jq -r .status "$STATE_ROOT/BG-1/state.json")" = BUILDING ]
}

@test "invalid Guardian verdicts and exceeded revision limits block" {
  init_task
  submit_handoff
  make_fake_codex
  sed -i 's/verdict:"APPROVED"/verdict:"INVALID"/' "$FAKE_CODEX"
  run "$HARNESS" --state-root "$STATE_ROOT" review BG-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid Guardian verdict"* ]]

  jq '.review_cycle=2 | .status="AWAITING_REVIEW"' "$STATE_ROOT/BG-1/state.json" > "$STATE_ROOT/limit"
  mv "$STATE_ROOT/limit" "$STATE_ROOT/BG-1/state.json"
  run "$HARNESS" --state-root "$STATE_ROOT" review BG-1
  [ "$status" -eq 2 ]
  [[ "$output" == *REVISION_LIMIT_REACHED* ]]
}
