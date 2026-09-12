#!/usr/bin/env bats

# Test of the joint reset of `model_index` and the streak sentinel
# when switching effort level, when the fallback lists of the old
# and new levels have different lengths
# (plan/02.md, final subtask: "with lists of different lengths").
#
# catalogo-agentes.md documents the three real lists:
# fallback.default.low has 3 models, medium and high have 4. A
# `model_index` valid in a list of 4 (e.g. 3) falls out of
# range in the list of 3 of the low level if it is not reset when
# switching level. `gubia effort set` resets `model_index` to 0 in the
# same invocation (task already implemented); this test checks that
# that reset, together with the `state_read` one for the streak
# sentinel, leaves the state consistent with the new level's list
# regardless of its length.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  state_ensure
}

@test "medium (list of 4) -> low (list of 3): model_index and streak are reset" {
  state_read
  # State of a medium iteration with the list of 4 almost fully
  # exhausted and a streak in progress.
  state_set model_index 3
  state_streak_index=2

  cmd_effort_set low

  # The file is left consistent with the new level before re-reading it.
  grep -q '^effort_level=low$' .gubia/state.env
  grep -q '^model_index=0$' .gubia/state.env

  # The iteration-start re-read (the loop's one) detects the level
  # change and clears the streak sentinel.
  state_read
  [ -z "$state_streak_index" ]
  [ "$model_index" -eq 0 ]

  # The resulting index already fits in the new list, of length 3.
  state_guard_model_index 3
  [ "$model_index" -eq 0 ]
}

@test "low (list of 3) -> high (list of 4): model_index and streak are reset" {
  state_read
  state_set model_index 2
  state_streak_index=1

  cmd_effort_set high

  grep -q '^effort_level=high$' .gubia/state.env
  grep -q '^model_index=0$' .gubia/state.env

  state_read
  [ -z "$state_streak_index" ]
  [ "$model_index" -eq 0 ]

  state_guard_model_index 4
  [ "$model_index" -eq 0 ]
}

@test "without a level change, a model_index out of the new list is not corrected on its own" {
  # Control: if the level does not change, `state_read` touches neither
  # the sentinel nor `model_index` — only `cmd_effort_set` or the
  # explicit guard do. Makes clear that the reset depends on the level
  # change, not on any re-read.
  state_read
  state_set model_index 3
  state_streak_index=2

  sed -i 's|^effort_level=.*|effort_level=medium|' .gubia/state.env
  state_read

  [ "$state_streak_index" -eq 2 ]
  [ "$model_index" -eq 3 ]
}
