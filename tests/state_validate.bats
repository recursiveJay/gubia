#!/usr/bin/env bats

# Test of the `state_validate` range validator (plan/02.md): covers
# `effort_level` and `thinking` as abortive validation (exit 2, naming
# key and value), and the `model_index` guard
# (`state_guard_model_index`) as a non-abortive case within the same
# test file, as the subtask asks. The abortive range of `model_index`
# itself (integer >= 0) is already covered in `state_model_index.bats`
# alongside the rest of its non-abortive guard; here the non-abortive
# guard is tested again to keep the three cases (`effort_level`,
# `thinking`, `model_index`) together in a single file, as the active
# subtask asks.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  state_ensure
}

write_state() {
  printf '%s\n' \
    "effort_level=$1" \
    'fallback_list=default' \
    'model_index=0' \
    "thinking=$2" \
    'memory_max=8G' \
    'loop_max_logs=20' >.gubia/state.env
}

@test "valid effort_level (low|medium|high) does not abort" {
  for level in low medium high; do
    write_state "$level" true
    state_read
    run state_validate
    [ "$status" -eq 0 ]
  done
}

@test "out-of-range effort_level aborts with exit 2 naming key and value" {
  write_state bogus true
  state_read
  run state_validate
  [ "$status" -eq 2 ]
  grep -q 'effort_level' <<<"$output"
  grep -q 'bogus' <<<"$output"
}

@test "valid thinking (true|false) does not abort" {
  for value in true false; do
    write_state medium "$value"
    state_read
    run state_validate
    [ "$status" -eq 0 ]
  done
}

@test "out-of-range thinking aborts with exit 2 naming key and value" {
  write_state medium maybe
  state_read
  run state_validate
  [ "$status" -eq 2 ]
  grep -q 'thinking' <<<"$output"
  grep -q 'maybe' <<<"$output"
}

@test "out-of-range model_index guard of the active list does not abort: resets to 0" {
  write_state medium true
  state_read
  run state_validate
  [ "$status" -eq 0 ]
  model_index=7
  state_guard_model_index 3
  [ "$model_index" -eq 0 ]
}
