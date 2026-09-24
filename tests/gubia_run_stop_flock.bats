#!/usr/bin/env bats

# e2e test of the two concurrency exits of the loop
# (plan/06.md: "Implement the stop file check before each iteration of
# the `gubia run` loop, stopping if it exists" and
# "vault/spec/engine.md", "Concurrency": the per-plan `flock`).
#
# The two existing bats tests touch each piece separately
# (`gubia_run_max_iterations.bats` tests the stop file against an agent
# that exits instantly; `gubia_effort_set.bats` tests the lock against
# `effort set`, which does not take it). What is missing, and is the
# point of this file, is the e2e scenario with two real `gubia run`s:
# one holding the lock with an iteration in progress, and a second
# `gubia run` on the same plan colliding against it; and the stop file
# created while the first is still alive, cutting off its next turn
# without invoking the agent again.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  bin="$repo/bin"
  mkdir -p "$bin" config plan
  printf '# Plan\n- [ ] [00. task](plan/00.md)\n' >plan/plan.md
  holder_pid=
}

teardown() {
  if [[ -n "$holder_pid" ]]; then
    kill "$holder_pid" 2>/dev/null || true
    wait "$holder_pid" 2>/dev/null || true
  fi
  cd /
  rm -rf "$repo"
}

ticks() {
  grep -c '^tick$' "$repo/agent.marker" 2>/dev/null || printf '0\n'
}

# Fake agent that signs each start and then sleeps: keeps the iteration
# (and with it the `flock`) open for the whole test.
write_sleeping_agent() {
  cat >"$bin/sleep-cli" <<'CLI'
#!/usr/bin/env bash
printf 'tick\n' >>"$AGENT_MARKER"
sleep 60
CLI
  chmod +x "$bin/sleep-cli"
  cat >config/agents.sh <<EOF
declare -rA GUBIA_MODELS=([claude-test]='claude fake')
declare -ra GUBIA_FALLBACK_LOW=(claude-test)
declare -ra GUBIA_FALLBACK_MEDIUM=(claude-test)
declare -ra GUBIA_FALLBACK_HIGH=(claude-test)
agent_claude() {
  GUBIA_PROMPT_MODE='file'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=("$bin/sleep-cli")
  GUBIA_ENV=("AGENT_MARKER=$repo/agent.marker")
}
EOF
}

# Same as the one above, but immediate exit 0: for the stop-file-between-
# turns scenario, where what matters is that there is NOT one extra
# invocation, not keeping the lock held.
write_fast_agent() {
  cat >"$bin/tick-cli" <<'CLI'
#!/usr/bin/env bash
printf 'tick\n' >>"$AGENT_MARKER"
exit 0
CLI
  chmod +x "$bin/tick-cli"
  cat >config/agents.sh <<EOF
declare -rA GUBIA_MODELS=([claude-test]='claude fake')
declare -ra GUBIA_FALLBACK_LOW=(claude-test)
declare -ra GUBIA_FALLBACK_MEDIUM=(claude-test)
declare -ra GUBIA_FALLBACK_HIGH=(claude-test)
agent_claude() {
  GUBIA_PROMPT_MODE='file'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=("$bin/tick-cli")
  GUBIA_ENV=("AGENT_MARKER=$repo/agent.marker")
}
EOF
}

# Waits for the plan lockfile to exist AND be actually held: existence
# alone is not enough, `exec 9>` creates it before `flock` runs.
wait_for_lock() {
  local lock="$repo/.gubia/plan-plan.md.lock" i
  for ((i = 0; i < 100; i++)); do
    if [[ -e "$lock" ]] && ! flock -n "$lock" true; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

@test "a second gubia run on the same plan collides with the first one's lock" {
  write_sleeping_agent
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    "$GUBIA_BIN" run plan/plan.md 5 >"$repo/run.log" 2>&1 &
  holder_pid=$!
  wait_for_lock

  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    run timeout 10 "$GUBIA_BIN" run plan/plan.md 5
  [ "$status" -eq 1 ]
  grep -q 'lock busy' <<<"$output"
  # The collision is immediate (`flock -n`), not a wait: the second
  # process never gets to invoke its own agent.
  [ "$(ticks)" -eq 1 ]

  # The first is still alive with its lock intact: the second neither
  # stole it nor knocked it down when failing.
  kill -0 "$holder_pid"
  ! flock -n "$repo/.gubia/plan-plan.md.lock" true
}

@test "after releasing the lock (dead process), a new gubia run can take it" {
  write_sleeping_agent
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    "$GUBIA_BIN" run plan/plan.md 5 >"$repo/run.log" 2>&1 &
  holder_pid=$!
  wait_for_lock

  kill "$holder_pid"
  wait "$holder_pid" 2>/dev/null || true
  holder_pid=

  write_fast_agent
  rm -f "$repo/agent.marker"
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    run "$GUBIA_BIN" run plan/plan.md 2
  [ "$status" -eq 0 ]
  [ "$(ticks)" -eq 2 ]
}

@test "the stop file created between turns stops the next iteration without an extra invocation" {
  write_fast_agent
  # Large `max_iterations`: if the stop file did not cut it off, the
  # loop would keep turning and the test would notice it by the final
  # count.
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    "$GUBIA_BIN" run plan/plan.md 1000 >"$repo/run.log" 2>&1 &
  holder_pid=$!
  wait_for_lock

  # At least one turn already ran (the lock is held); now the stop is
  # requested and we wait for the process to obey it on its own,
  # without killing it.
  printf 'parada\n' >plan/stop.md
  local i
  for ((i = 0; i < 100; i++)); do
    kill -0 "$holder_pid" 2>/dev/null || break
    sleep 0.1
  done
  ! kill -0 "$holder_pid" 2>/dev/null
  wait "$holder_pid"
  local exit_code=$?
  [ "$exit_code" -eq 0 ]
  holder_pid=

  grep -q 'stop file present' "$repo/run.log"
  ! grep -q 'max_iterations reached' "$repo/run.log"
  # The lock is released (dead process) but the file stays ("the
  # lockfile is never deleted"): another `gubia run` can take it.
  flock -n "$repo/.gubia/plan-plan.md.lock" true
}
