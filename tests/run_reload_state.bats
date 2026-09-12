#!/usr/bin/env bats

# Test of the `state.env` re-read at the start of each iteration
# (plan/06.md: "Implement the `state.env` re-read at the start of each
# iteration of the `gubia run` loop").
#
# What is observed is that the state an iteration uses is the one in
# the file NOW and not the one read at startup: between two iterations
# the agent (`gubia effort set`, another process) and the engine itself
# (`model_index` rotation) write. The three blocks cover the three
# effects of the re-read: fresh values, streak sentinel reset on level
# change, and abortive validation of what was re-read.
#
# The last block is e2e over `gubia run` with the catalog's
# `agent_probe`: the probe dumps its environment, and `state_read`
# exports the 6 keys, so the dump proves the child received the state
# written AFTER the engine started.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  state_ensure
}

@test "the re-read sees writes made after the startup read" {
  # Engine startup: initial read with the defaults.
  state_read
  state_validate
  [ "$effort_level" = medium ]
  [ "$model_index" -eq 0 ]

  # Writes in between: the agent changes the level from another
  # process and the engine rotates the index.
  state_set effort_level high
  state_set model_index 2

  run_reload_state

  [ "$effort_level" = high ]
  [ "$model_index" -eq 2 ]
}

@test "the re-read clears the streak sentinel on level change" {
  state_read
  state_validate
  state_streak_index=1

  # Without a level change, the streak survives the re-read.
  run_reload_state
  [ "$state_streak_index" -eq 1 ]

  # With a level change (the one `gubia effort set` wrote from inside
  # the previous iteration), the re-read clears it: the saved index was
  # from another level's list.
  state_set effort_level low
  run_reload_state
  [ -z "$state_streak_index" ]
}

@test "an invalid value written between iterations aborts on the re-read" {
  state_read
  state_validate

  state_set thinking maybe

  run run_reload_state
  [ "$status" -eq 2 ]
  grep -q 'thinking' <<<"$output"
  grep -q 'maybe' <<<"$output"
}

@test "gubia run invokes the agent with the file's state, not the startup one" {
  mkdir -p plan config
  printf '# plan\n- [ ] [00. task](plan/00.md)\n' >plan/plan.md
  # State written before the invocation: it is the one the
  # start-of-iteration re-read must export to the agent's environment.
  state_set effort_level high
  state_set thinking false

  # Isolated catalog that resolves the active entry of the `high` level
  # (model_index 0, the only value this test operates with) to the real
  # `agent_probe`: it is the one that dumps the received environment.
  cat >config/agents.sh <<EOF
declare -rA GUBIA_MODELS=([probe-test]='probe fake')
declare -ra GUBIA_FALLBACK_LOW=(probe-test)
declare -ra GUBIA_FALLBACK_MEDIUM=(probe-test)
declare -ra GUBIA_FALLBACK_HIGH=(probe-test)
agent_probe() {
  GUBIA_PROMPT_MODE='stdin'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=("${BATS_TEST_DIRNAME}/../scripts/agent-probe.sh")
  GUBIA_ENV=()
}
EOF

  # `max_iterations=1`: the probe exits with 0 and does not create a
  # stop file, so without a ceiling the engine would spin the default
  # 500 turns. A single iteration is enough for what this test observes.
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
  GUBIA_PROBE_DUMP="${repo}/dump.txt" \
    run "$GUBIA_BIN" run plan/plan.md 1
  [ "$status" -eq 0 ]

  grep -q '^effort_level=high$' "${repo}/dump.txt"
  grep -q '^thinking=false$' "${repo}/dump.txt"
}
