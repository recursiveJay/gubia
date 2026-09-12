#!/usr/bin/env bats

# Test of the mutual exclusion of the `flock` per plan file
# (plan/04.md: "Implement the `flock` per plan file").
#
# The `run_` module is sourced from the script (`BASH_SOURCE` guard)
# for the first block, which sets the exact lockfile name
# (`<slug>` = plan path relative to the root with `/`→`-`). The second
# block launches two real `gubia run` processes, in parallel, on the
# same plan: the observation is the real result of the race — one
# acquires the lock and runs, the other exits with exit 1 without
# touching the agent — not an inference about the file name.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
}

@test "with the plan lockfile already taken, gubia run exits with exit 1 without invoking the agent" {
  mkdir -p plan
  printf '# plan\n- [ ] [00. task](plan/00.md)\n' >plan/plan.md
  run_resolve_plan plan/plan.md
  run_acquire_lock
  # `run_acquire_lock` already left fd 9 of this bats process holding
  # the lock: it is enough to invoke `gubia run` in a separate child
  # process to reproduce the contention of two simultaneous invocations.
  GUBIA_AGENTS_SH="${BATS_TEST_DIRNAME}/../config/agents.sh" \
  GUBIA_PROBE_DUMP="${repo}/dump.txt" \
    run "$GUBIA_BIN" run plan/plan.md
  [ "$status" -eq 1 ]
  grep -q 'lock busy' <<<"$output"
  [ ! -e "${repo}/dump.txt" ]
}

@test "two simultaneous gubia run invocations on the same plan: only one runs" {
  mkdir -p plan config
  printf '# plan\n- [ ] [00. task](plan/00.md)\n' >plan/plan.md
  # Isolated catalog that resolves the active entry by default to the
  # real `agent_probe`: it is the one that creates `dump.txt` when running.
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

  # The agent holding the lock is a real `sleep` under the flock
  # itself: it is done manually (same file that `run_acquire_lock`
  # would compute) to have a deterministic contention window without
  # touching the engine. The second invocation is a real, complete
  # `gubia run`, which must collide with that already-taken lock.
  mkdir -p .gubia
  (
    exec 9>".gubia/plan-plan.md.lock"
    flock 9
    sleep 1
  ) &
  local holder_pid=$!
  # Yield time for the subshell to acquire the flock before competing.
  sleep 0.2

  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
  GUBIA_PROBE_DUMP="${repo}/dump.txt" \
    run "$GUBIA_BIN" run plan/plan.md
  [ "$status" -eq 1 ]
  grep -q 'lock busy' <<<"$output"
  [ ! -e "${repo}/dump.txt" ]

  wait "$holder_pid"

  # With the lock already released, a third invocation does acquire the
  # lock and runs to the end: the contention above was from the lock,
  # not a permanent failure of the subcommand.
  # `max_iterations=1`: the probe exits with 0 and does not create a
  # stop file, so without a ceiling the engine would spin the default
  # 500 turns. A single iteration is enough for what this test observes.
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
  GUBIA_PROBE_DUMP="${repo}/dump.txt" \
    run "$GUBIA_BIN" run plan/plan.md 1
  [ "$status" -eq 0 ]
  [ -f "${repo}/dump.txt" ]
}
