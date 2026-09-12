#!/usr/bin/env bats

# Round-trip test for writing `state.env` (plan/02.md, last subtask):
# write a key with `state_set`, re-read the file from scratch
# (`state_read`, without `source`-ing the file) and check that the
# written value persists both on disk and in the exported variable.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  state_ensure
}

@test "state_set persists the value: it is re-read from disk after writing" {
  state_read
  [ "$loop_max_logs" -eq 20 ]

  state_set loop_max_logs 42

  # The value is on disk immediately.
  grep -q '^loop_max_logs=42$' .gubia/state.env

  # And an independent re-read of the process picks it up.
  unset loop_max_logs
  state_read
  [ "$loop_max_logs" -eq 42 ]
}

@test "state_set persists the value after reopening the file in a new process" {
  state_set memory_max 4G

  run bash -c "source '$GUBIA_BIN'; state_read; printf '%s\n' \"\$memory_max\""
  [ "$status" -eq 0 ]
  [ "$output" = "4G" ]
}
