#!/usr/bin/env bats

# E2E test of the circular rotation of `model_index` and of the
# exhaustion of the streak sentinel (plan/06.md: "Add a bats-core test
# (e2e with a fake CLI in the `PATH`, scripted exit codes) that
# verifies the circular rotation and the exhaustion of the streak
# sentinel").
#
# The fake CLI consumes, invocation by invocation, a list of exit codes
# scripted in advance in a file (`exit_queue.txt`) and leaves a trace
# of the `model_index` it was invoked with (`marker.txt`): this way,
# from outside the process, both the circular wrap of the index and the
# rc each iteration saw are observed.
#
# The test catalog's `agent_probe` reads `$model_index` directly — it
# is a bash function sourced in the same process as `gubia run`, not a
# separate binary — so the value it packages into the fake CLI's
# environment is the one `run_reload_state` just re-read for that
# iteration, the same one the circular rotation moves.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  bin="$repo/bin"
  mkdir -p "$bin" config plan .gubia
  cat >"$bin/rotate-cli" <<'CLI'
#!/usr/bin/env bash
set -euo pipefail
seq=1
[ -f "$SEQ_STATE" ] && seq="$(cat "$SEQ_STATE")"
printf '%s\n' "$((seq + 1))" >"$SEQ_STATE"
code="$(sed -n "${seq}p" "$EXIT_QUEUE")"
printf '%s\n' "$MODEL_INDEX" >>"$MARKER"
exit "${code:-1}"
CLI
  chmod +x "$bin/rotate-cli"
  # Test catalog: a 3-model fallback list under `low` (the content of
  # each entry is irrelevant, only the length counts) and an
  # `agent_probe` that forwards `$model_index` — a global variable
  # already re-read by `run_reload_state` — to the fake CLI.
  cat >config/agents.sh <<EOF
declare -rA GUBIA_MODELS=(
  [m0]='claude fake-0'
  [m1]='claude fake-1'
  [m2]='claude fake-2'
)
declare -ra GUBIA_FALLBACK_LOW=(m0 m1 m2)
agent_claude() {
  GUBIA_PROMPT_MODE='file'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=("$bin/rotate-cli")
  GUBIA_ENV=(
    "MODEL_INDEX=\$model_index"
    "EXIT_QUEUE=$repo/exit_queue.txt"
    "SEQ_STATE=$repo/seq_state.txt"
    "MARKER=$repo/marker.txt"
  )
}
EOF
  printf '# Plan\n- [ ] [00. task](plan/00.md)\n' >plan/plan.md
  cat >.gubia/state.env <<'ENV'
effort_level=low
fallback_list=default
model_index=0
thinking=true
memory_max=8G
loop_max_logs=20
ENV
}

teardown() {
  cd /
  rm -rf "$repo"
}

markers() {
  cat "$repo/marker.txt" 2>/dev/null || true
}

@test "circular rotation: fail, fail, success resets the streak, fails again and wraps the index" {
  printf '1\n1\n0\n1\n1\n0\n' >exit_queue.txt
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    run "$GUBIA_BIN" run plan/plan.md 6
  [ "$status" -eq 0 ]
  # model_index sequence observed by each invocation: 0,1 fail (rotates
  # 0->1->2); 2 succeeds (resets the streak, does not rotate, stays at
  # 2); 2,0 fail again (rotates 2->0->1, wrapping the index after the
  # last model in the list); 1 succeeds.
  [ "$(markers)" = "$(printf '0\n1\n2\n2\n0\n1\n')" ]
  grep -q 'max_iterations reached (6)' <<<"$output"
}

@test "streak sentinel exhaustion: three consecutive failures with no success in between abort with fallback-exhausted" {
  printf '1\n1\n1\n1\n1\n' >exit_queue.txt
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    run "$GUBIA_BIN" run plan/plan.md 5
  [ "$status" -eq 3 ]
  # The streak is marked at index 0 (the first failure); each failure
  # rotates the index BEFORE checking the mark, so the wrap is detected
  # right after completing the 3-model list: 0 fails and rotates to 1,
  # 1 fails and rotates to 2, 2 fails and rotates back to 0 — which
  # matches the mark — and aborts there, without a fourth real
  # invocation. Only the 3 invocations of the 5 in the ceiling are seen.
  [ "$(markers)" = "$(printf '0\n1\n2\n')" ]
  grep -q 'fallback-exhausted' <<<"$output"
  grep -q 'model_index=0' <<<"$output"
}
