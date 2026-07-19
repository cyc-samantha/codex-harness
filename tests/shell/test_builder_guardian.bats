#!/usr/bin/env bats

load helper

setup() {
  make_repo_with_worktree
  STATE_ROOT="$(cxh_mktemp_dir)"
  HARNESS="${BATS_TEST_DIRNAME}/../../scripts/codex-harness"
  CONTRACT="$STATE_ROOT/contract.json"
  BASE_SHA="$(git -C "$REPO_DIR" rev-parse HEAD)"
  mkdir -p "$REPO_DIR/tests"
  mkdir -p "$WORKTREE_DIR/tests"
  echo changed >> "$WORKTREE_DIR/seed"
  echo regression > "$WORKTREE_DIR/tests/unit"
  git -C "$WORKTREE_DIR" add seed tests/unit
  git -C "$WORKTREE_DIR" commit -qm target
  HEAD_SHA="$(git -C "$WORKTREE_DIR" rev-parse HEAD)"
  make_contract
}

teardown() {
  cxh_cleanup
  [[ -n "${STATE_ROOT:-}" ]] && rm -rf "$STATE_ROOT"
}

make_contract() {
  jq -n --arg repo "$REPO_DIR" --arg sha "$BASE_SHA" '{
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
  jq -n --arg repo "$REPO_DIR" --arg worktree "$WORKTREE_DIR" --arg target "$HEAD_SHA" --arg base "$BASE_SHA" '{
    task_id:"BG-1",review_target:$target,base_commit:$base,changed_files:["seed","tests/unit"],summary:"done",
    ac_evidence:{"AC-1":"test"},tests_changed:["tests/unit"],commands:["true"],
    results:[{command:"true",passed:true}],limitations:[],risks:[],builder_session_id:"builder-1",
    worktree:$worktree,branch:"feat/x",repository:$repo
  }' > "$STATE_ROOT/handoff-input.json"
}

submit_handoff() {
  make_handoff
  run env PYTHONPATH="${BATS_TEST_DIRNAME}/../../scripts/lib" python3 -c \
    'import json,sys; from pathlib import Path; from builder_guardian_state import PipelineState; state=PipelineState.open(Path(sys.argv[1]), sys.argv[2]); state.accept_handoff(json.loads(Path(sys.argv[3]).read_text()))' \
    "$STATE_ROOT" BG-1 "$STATE_ROOT/handoff-input.json"
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

  jq '.final_checks=[]' "$CONTRACT" > "$CONTRACT.bad"
  run "$HARNESS" --state-root "$STATE_ROOT" init "$CONTRACT.bad"
  [ "$status" -eq 2 ]

  jq '.acceptance_criteria[0].verification=["bad"]' "$CONTRACT" > "$CONTRACT.bad"
  run "$HARNESS" --state-root "$STATE_ROOT" init "$CONTRACT.bad"
  [ "$status" -eq 2 ]
  [[ "$output" == *INVALID_TASK_CONTRACT* ]]
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

@test "Builder completion automatically launches Guardian on the actual patch" {
  init_task
  FAKE_BUILDER="$STATE_ROOT/fake-builder"
  cat > "$FAKE_BUILDER" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${BUILDER_ARGS_LOG}"
output=""
cwd=""
prompt="${*: -1}"
while (($#)); do
  [[ "$1" == "--output-last-message" ]] && { output="$2"; shift 2; continue; }
  [[ "$1" == "--cd" ]] && { cwd="$2"; shift 2; continue; }
  shift
done
if [[ "$prompt" == *"You are the Guardian Codex"* ]]; then
  task="$(sed -n 's#Task Contract: .*/\([^/]*\)/contract.json#\1#p' <<< "$prompt")"
  target="$(sed -n 's/^Fixed review target: //p' <<< "$prompt")"
  session="$(sed -n 's/^Guardian session ID: //p' <<< "$prompt")"
  repo="$(sed -n 's/^Repository identity: //p' <<< "$prompt")"
  worktree="$(sed -n 's/^Worktree identity: //p' <<< "$prompt")"
  run_id="$(sed -n 's/^Pipeline run ID: //p' <<< "$prompt")"
  jq -n --arg task "$task" --arg target "$target" --arg session "$session" --arg repo "$repo" --arg worktree "$worktree" --arg run "$run_id" '{verdict:"APPROVED",task_id:$task,reviewed_target:$target,guardian_session_id:$session,repository:$repo,worktree:$worktree,run_id:$run,ac_results:[{id:"AC-1",result:"PASS",justification:"reviewed patch"}],blocking_findings:[],non_blocking_findings:[],missing_evidence:[],commands:["git diff"],timestamp:"2026-07-18T00:00:00Z"}' > "$output"
  exit 0
fi
echo built >> "$cwd/seed"
mkdir -p "$cwd/tests"
echo regression > "$cwd/tests/unit"
git -C "$cwd" add seed tests/unit
git -C "$cwd" commit -qm build
target="$(git -C "$cwd" rev-parse HEAD)"
base="$(git -C "$cwd" rev-parse HEAD^)"
jq -n --arg target "$target" --arg base "$base" '{review_target:$target,base_commit:$base,changed_files:["seed","tests/unit"],summary:"built",ac_evidence:{"AC-1":"test"},tests_changed:["tests/unit"],commands:["true"],results:[{command:"true",passed:true}],limitations:[],risks:[]}' > "$output"
SH
  chmod +x "$FAKE_BUILDER"
  export CODEX_BIN="$FAKE_BUILDER"
  export BUILDER_ARGS_LOG="$STATE_ROOT/builder-args"
  run "$HARNESS" --state-root "$STATE_ROOT" build BG-1
  [ "$status" -eq 0 ]
  [ "$(jq -r .status <<< "$output")" = GUARDIAN_APPROVED ]
  grep -q -- '--sandbox workspace-write' "$BUILDER_ARGS_LOG"
  grep -q -- '--sandbox read-only' "$BUILDER_ARGS_LOG"
  grep -q -- '<reviewed_patch>' "$BUILDER_ARGS_LOG"
  grep -q -- '+built' "$BUILDER_ARGS_LOG"
  [[ "$(jq -r .worktree "$STATE_ROOT/BG-1/handoff.json")" == *builder-BG-1 ]]
}

@test "Guardian runs in fresh ephemeral read-only context and approval is commit-bound" {
  init_task
  make_handoff
  make_fake_codex
  run "$HARNESS" --state-root "$STATE_ROOT" handoff BG-1 "$STATE_ROOT/handoff-input.json"
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
  sed -i 's/blocking_findings:\[\]/blocking_findings:[{id:"BG-1",severity:"HIGH",component:"seed",description:"failure",requirement:"AC-1",resolution:"fix",evidence:"inspection"}]/' "$FAKE_CODEX"
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
  echo dirty > "$WORKTREE_DIR/dirty"
  run "$HARNESS" --state-root "$STATE_ROOT" verify BG-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"worktree does not match"* ]]
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
  jq '.verdict="APPROVED"' "$STATE_ROOT/BG-1/guardian-verdict.json" > "$STATE_ROOT/restored"
  mv "$STATE_ROOT/restored" "$STATE_ROOT/BG-1/guardian-verdict.json"
  jq '.commands[0].exit_code=1 | .status="FAILED"' "$STATE_ROOT/BG-1/verification.json" > "$STATE_ROOT/tampered"
  mv "$STATE_ROOT/tampered" "$STATE_ROOT/BG-1/verification.json"
  run "$HARNESS" --state-root "$STATE_ROOT" gate BG-1
  [ "$status" -eq 2 ]
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

@test "fabricated Builder check evidence is rejected by independent execution" {
  jq '.builder_checks=[{name:"must-fail",command:"false"}]' "$CONTRACT" > "$CONTRACT.tmp"
  mv "$CONTRACT.tmp" "$CONTRACT"
  init_task
  make_handoff
  jq '.results=[{command:"false",passed:true}]' "$STATE_ROOT/handoff-input.json" > "$STATE_ROOT/fake"
  run "$HARNESS" --state-root "$STATE_ROOT" handoff BG-1 "$STATE_ROOT/fake"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Builder validation failed"* ]]
}

@test "empty Guardian rejection findings are invalid" {
  init_task
  submit_handoff
  make_fake_codex
  sed -i 's/verdict:"APPROVED"/verdict:"CHANGES_REQUESTED"/' "$FAKE_CODEX"
  sed -i 's/ac_results:\[{id:"AC-1",result:"PASS"/ac_results:[{id:"AC-1",result:"FAIL"/' "$FAKE_CODEX"
  run "$HARNESS" --state-root "$STATE_ROOT" review BG-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"without actionable findings"* ]]
}

@test "tampered approval and passing-command evidence cannot ship" {
  init_task
  submit_handoff
  approve
  run "$HARNESS" --state-root "$STATE_ROOT" verify BG-1
  [ "$status" -eq 0 ]
  jq '.verdict="CHANGES_REQUESTED"' "$STATE_ROOT/BG-1/guardian-verdict.json" > "$STATE_ROOT/tampered"
  mv "$STATE_ROOT/tampered" "$STATE_ROOT/BG-1/guardian-verdict.json"
  run "$HARNESS" --state-root "$STATE_ROOT" gate BG-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"stale evidence"* ]]
}

@test "repository root cannot impersonate an isolated Builder worktree" {
  init_task
  make_handoff
  jq --arg repo "$REPO_DIR" '.worktree=$repo | .branch="main"' "$STATE_ROOT/handoff-input.json" > "$STATE_ROOT/root-handoff"
  run "$HARNESS" --state-root "$STATE_ROOT" handoff BG-1 "$STATE_ROOT/root-handoff"
  [ "$status" -eq 2 ]
  [[ "$output" == *"isolated worktree"* ]]
}

@test "post-verification handoff tampering cannot ship" {
  init_task
  submit_handoff
  approve
  run "$HARNESS" --state-root "$STATE_ROOT" verify BG-1
  [ "$status" -eq 0 ]
  jq '.changed_files=["forged"]' "$STATE_ROOT/BG-1/handoff.json" > "$STATE_ROOT/tampered"
  mv "$STATE_ROOT/tampered" "$STATE_ROOT/BG-1/handoff.json"
  run "$HARNESS" --state-root "$STATE_ROOT" gate BG-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"stale Builder handoff"* ]]
}

@test "Guardian findings must map exactly to failed criteria" {
  init_task
  submit_handoff
  make_fake_codex
  sed -i 's/verdict:"APPROVED"/verdict:"CHANGES_REQUESTED"/' "$FAKE_CODEX"
  sed -i 's/result:"PASS"/result:"FAIL"/' "$FAKE_CODEX"
  sed -i 's/blocking_findings:\[\]/blocking_findings:[{id:"BG-X",severity:"HIGH",component:"seed",description:"failure",requirement:"UNKNOWN",resolution:"fix",evidence:"inspection"}]/' "$FAKE_CODEX"
  run "$HARNESS" --state-root "$STATE_ROOT" review BG-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"without actionable findings"* ]]
}

@test "duplicate Guardian AC results are rejected" {
  init_task
  submit_handoff
  make_fake_codex
  printf '%s\n' 'jq '\''.ac_results += [.ac_results[0]]'\'' "$output" > "$output.tmp" && mv "$output.tmp" "$output"' >> "$FAKE_CODEX"
  run "$HARNESS" --state-root "$STATE_ROOT" review BG-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"incomplete AC review"* ]]
}

@test "handoff admission rejects every in-flight and terminal state" {
  init_task
  make_handoff
  for pipeline_state in BLOCKED VERIFYING VERIFIED READY_TO_SHIP; do
    jq --arg value "$pipeline_state" '.status=$value' "$STATE_ROOT/BG-1/state.json" > "$STATE_ROOT/changed-state"
    mv "$STATE_ROOT/changed-state" "$STATE_ROOT/BG-1/state.json"
    run "$HARNESS" --state-root "$STATE_ROOT" handoff BG-1 "$STATE_ROOT/handoff-input.json"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not admitted"* ]]
    [ "$(jq -r .status "$STATE_ROOT/BG-1/state.json")" = "$pipeline_state" ]
  done
}

@test "ready evidence cannot be superseded by a later handoff" {
  init_task
  submit_handoff
  approve
  run "$HARNESS" --state-root "$STATE_ROOT" verify BG-1
  [ "$status" -eq 0 ]
  run "$HARNESS" --state-root "$STATE_ROOT" gate BG-1
  [ "$status" -eq 0 ]
  ready_hash="$(sha256sum "$STATE_ROOT/BG-1/ready.json" | awk '{print $1}')"
  run "$HARNESS" --state-root "$STATE_ROOT" handoff BG-1 "$STATE_ROOT/handoff-input.json"
  [ "$status" -eq 2 ]
  [ "$(sha256sum "$STATE_ROOT/BG-1/ready.json" | awk '{print $1}')" = "$ready_hash" ]
  [ "$(jq -r .status "$STATE_ROOT/BG-1/state.json")" = READY_TO_SHIP ]
}
