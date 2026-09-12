#!/usr/bin/env bats

# Test of the streak sentinel reset when `effort_level` changes
# (plan/02.md: "the streak sentinel reset (in `run` process memory)
# when the start-of-iteration re-read detects that `effort_level`
# changed since the previous iteration").
#
# The sentinel (`state_streak_index`) and the level seen in the
# previous re-read (`state_prev_effort`) live in `run` process
# memory, not on disk: they are `state_` module variables and the
# loop (task 06) sets the sentinel when an iteration fails. Here we
# test directly the detection embedded in `state_read`: the engine
# calls `state_read` at the start of each iteration, so that is the
# point where a level change must clear the streak
# (vault/spec/motor.md, "Consistency when changing effort level": the
# agent wrote the level from another process via `gubia effort set`;
# the engine only sees it on re-read).

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  state_ensure
}

# Simulates a loop re-read after a level change written by the agent:
# rewrites the `effort_level` line in `state.env` (what `gubia effort
# set` does in another process) and re-reads.
set_effort_in_file() {
  sed -i "s|^effort_level=.*|effort_level=$1|" .gubia/state.env
  state_read
}

@test "changing effort_level between re-reads resets the streak sentinel" {
  # First loop read: no streak yet, sets the base level.
  state_read
  # The loop sets the sentinel when an iteration fails (task 06).
  state_streak_index=2
  # The agent changes the level from inside the iteration...
  set_effort_in_file high
  # ...and the start-of-iteration re-read of the next iteration detects
  # it and clears the streak: the saved index was from the old level's
  # list and would compare indices across different lists.
  [ -z "$state_streak_index" ]
}

@test "without an effort_level change the sentinel is preserved" {
  state_read
  state_streak_index=2
  set_effort_in_file medium
  [ "$state_streak_index" -eq 2 ]
}

@test "the first read does not reset (there can be no prior streak)" {
  state_streak_index=1
  state_read
  [ "$state_streak_index" -eq 1 ]
}

@test "resetting once does not reset again without a second change" {
  state_read
  state_streak_index=2
  set_effort_in_file high
  [ -z "$state_streak_index" ]
  # The loop sets the sentinel again at the new level; a re-read with
  # no change must not clear it.
  state_streak_index=0
  set_effort_in_file high
  [ "$state_streak_index" -eq 0 ]
}

@test "the sentinel is not persisted in state.env" {
  # The sentinel is `run` process memory: no `state_read` write may
  # touch the file.
  state_read
  state_streak_index=2
  set_effort_in_file low
  [ -z "$state_streak_index" ]
  ! grep -q 'streak' .gubia/state.env
  [ "$(grep -c . .gubia/state.env)" -eq 6 ]
}

@test "returning to the original level after a change also resets (level ≠ prev, not a fixed order)" {
  # medium -> high resets (above); high -> medium must also reset: the
  # comparison is against the previous re-read's level, not a hardcoded
  # sequence.
  state_read
  set_effort_in_file high
  state_streak_index=3
  set_effort_in_file medium
  [ -z "$state_streak_index" ]
}
