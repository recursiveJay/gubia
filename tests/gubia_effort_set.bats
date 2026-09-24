#!/usr/bin/env bats

# Test of the `gubia effort set <low|medium|high>` subcommand
# (plan/06.md: "Implement `gubia effort set <low|medium|high>` as a
# subcommand that does not acquire the `flock`").
#
# Here the BINARY is exercised, not the sourced functions: the
# internal coherence of the level change is already covered by
# tests/state_effort_switch_reset.bats calling `cmd_effort_set`
# directly. What is missing, and is the point of this file, is the
# real path by which the agent arrives — a new `gubia` process,
# dispatched from `main`, launched from INSIDE an iteration
# while the engine holds the plan's `flock`.
#
# That second part is the one with substance: if `effort set` took
# the plan lock, with `flock -n` it would die with exit 1 and with
# plain `flock` it would hang until the loop waiting on it died
# — self-deadlock. That is why the holder is a real `gubia run`
# (not a hand-rolled `flock`): what is observed is the scenario the
# spec describes, with the engine blocked waiting for its agent.

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

# Fake agent that stays asleep: keeps the iteration (and with it the
# `flock`) open for the whole test.
write_sleeping_agent() {
  cat >"$bin/sleep-cli" <<'CLI'
#!/usr/bin/env bash
printf 'started\n' >>"$AGENT_MARKER"
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

# Waits for the plan lockfile to exist AND be actually held: existence
# alone is not enough, `exec 9>` creates it before `flock` runs, and
# testing against a freshly created but free file would make the test
# pass with no contention at all.
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

@test "effort set writes the requested level to state.env, for all three levels" {
  local level
  for level in low high medium; do
    run "$GUBIA_BIN" effort set "$level"
    [ "$status" -eq 0 ]
    grep -q "^effort_level=${level}\$" .gubia/state.env
  done
}

@test "effort set only touches effort_level and model_index: the other four keys stay intact" {
  "$GUBIA_BIN" effort set low
  sed -i 's|^model_index=.*|model_index=2|;s|^loop_max_logs=.*|loop_max_logs=7|' .gubia/state.env

  run "$GUBIA_BIN" effort set high
  [ "$status" -eq 0 ]

  # The whole file, not just the changed key: a regeneration to the
  # defaults would also leave `effort_level=high`, and that would be a bug.
  diff - .gubia/state.env <<'EOF'
effort_level=high
fallback_list=default
model_index=0
thinking=true
memory_max=8G
loop_max_logs=7
EOF
}

@test "an invalid or absent level dies with exit 2 and leaves state.env as it was" {
  "$GUBIA_BIN" effort set high
  cp .gubia/state.env "$repo/before.env"

  local bad
  for bad in bogus LOW '' ' ' medium=high; do
    run "$GUBIA_BIN" effort set "$bad"
    [ "$status" -eq 2 ]
    diff "$repo/before.env" .gubia/state.env
  done
}

@test "effort set runs without blocking while gubia run holds the plan flock" {
  write_sleeping_agent
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    "$GUBIA_BIN" run plan/plan.md 1 >"$repo/run.log" 2>&1 &
  holder_pid=$!
  wait_for_lock

  # The agent already started: the iteration is in progress and the
  # engine waiting, which is exactly the moment the agent requests the
  # level change. `timeout` is the part that observes the "without
  # blocking": a `flock` without `-n` would hang here forever and the
  # test would fail with status 124 instead of getting stuck.
  [ -f "$repo/agent.marker" ]
  run timeout 10 "$GUBIA_BIN" effort set low
  [ "$status" -eq 0 ]
  grep -q '^effort_level=low$' .gubia/state.env

  # Neither contention nor its own lockfile: `effort set` does not
  # compete for the plan lock and does not invent another one.
  ! grep -q 'lock busy' <<<"$output"
  [ "$(find "$repo/.gubia" -name '*.lock' | wc -l)" -eq 1 ]

  # The loop is still alive with its lock intact: `effort set` did not
  # kill it or steal the file.
  kill -0 "$holder_pid"
  ! flock -n "$repo/.gubia/plan-plan.md.lock" true
}

@test "the plan lock stays exclusive to run while effort set passes by" {
  # Control for the previous case: `effort set` passing does not mean
  # the lock is loose. A second `gubia run` does collide, in between
  # two `effort set` calls that do not.
  write_sleeping_agent
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    "$GUBIA_BIN" run plan/plan.md 1 >"$repo/run.log" 2>&1 &
  holder_pid=$!
  wait_for_lock

  run timeout 10 "$GUBIA_BIN" effort set high
  [ "$status" -eq 0 ]

  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    run timeout 10 "$GUBIA_BIN" run plan/plan.md 1
  [ "$status" -eq 1 ]
  grep -q 'lock busy' <<<"$output"

  run timeout 10 "$GUBIA_BIN" effort set medium
  [ "$status" -eq 0 ]
  grep -q '^effort_level=medium$' .gubia/state.env
}
