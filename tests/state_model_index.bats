#!/usr/bin/env bats

# Test of the non-aborting range guard of `model_index`
# (plan/02.md: "out of range of the active list -> back to 0 with a
# warning on stderr, without aborting").
#
# The `state_` module is sourced from the script (`BASH_SOURCE`
# guard): the functions are tested directly with the keys exported by
# hand, without going through `main` — the length of the active list
# is passed by the engine as an argument (the `agents.sh` catalog of
# task 03 does not exist yet, and the design receives it by argument
# so that `state_` does not source global config).

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  state_ensure
}

# setup() with `source` under `set -u` inside bats is not a problem
# here: the BASH_SOURCE guard prevents `main` from running.

@test "model_index out of range of the active list returns to 0 with a stderr warning and without aborting" {
  # List of length 3 (low level in agents.toml), index 4: out.
  model_index=4
  state_guard_model_index 3
  # Without aborting: reaching here already proves there was no exit 2.
  [ "$model_index" -eq 0 ]
}

@test "model_index within range is preserved" {
  # List of length 4 (medium/high level in agents.toml).
  model_index=3
  state_guard_model_index 4
  [ "$model_index" -eq 3 ]
  model_index=0
  state_guard_model_index 4
  [ "$model_index" -eq 0 ]
}

@test "the out-of-range warning goes to stderr" {
  # Without aborting: exit 0 after the guard, with the warning only on stderr.
  model_index=4
  stderr_file="$(mktemp)"
  state_guard_model_index 3 2>"$stderr_file"
  [ "$model_index" -eq 0 ]
  grep -q 'model_index=4 out of range of the active list' "$stderr_file"
  grep -q 'falling back to 0' "$stderr_file"
}

@test "empty list (length 0) also resets" {
  model_index=0
  state_guard_model_index 0
  [ "$model_index" -eq 0 ]
}

@test "non-integer model_index is still aborting validation (exit 2)" {
  printf '%s\n' 'effort_level=medium' \
    'fallback_list=default' \
    'model_index=2x' \
    'thinking=true' \
    'memory_max=8G' \
    'loop_max_logs=20' >.gubia/state.env
  state_read
  run state_validate
  [ "$status" -eq 2 ]
  grep -q 'model_index' <<<"$output"
  grep -q '2x' <<<"$output"
}

@test "negative model_index is also aborting validation (exit 2)" {
  printf '%s\n' 'effort_level=medium' \
    'fallback_list=default' \
    'model_index=-1' \
    'thinking=true' \
    'memory_max=8G' \
    'loop_max_logs=20' >.gubia/state.env
  state_read
  run state_validate
  [ "$status" -eq 2 ]
  grep -q 'model_index' <<<"$output"
  grep -q '\-1' <<<"$output"
}