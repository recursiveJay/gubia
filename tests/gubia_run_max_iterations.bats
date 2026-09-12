#!/usr/bin/env bats

# Test of the loop iteration counter and its ceiling
# (plan/06.md: "Implement the `gubia run` loop iteration counter and its
# check against `max_iterations` (default 500), stopping with exit 0 when
# it is reached").
#
# What is observed is the REAL NUMBER of agent invocations, not an
# internal counter: the fake catalog agent appends a line to a marker on
# each start, so counting lines counts loop turns. A ceiling checked
# wrong (`<` instead of `<=`, counter starting at 0) would give a count
# different from the requested one, and that is exactly what these tests
# measure.
#
# The default 500 is not exercised by launching 500 iterations —that would
# be 500 processes per test— but over `run_resolve_max_iterations` with the
# script sourced, which is the function that sets it. What is exercised
# for real, with the whole engine, is the counting with small ceilings.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  bin="$repo/bin"
  mkdir -p "$bin" config plan
  # Fake agent that signs each start and exits 0: the loop has no reason
  # to stop because of it, so the only thing that can stop it is the
  # ceiling (or the stop file of the last test).
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
  printf '# Plan\n- [ ] [00. task](plan/00.md)\n' >plan/plan.md
}

teardown() {
  cd /
  rm -rf "$repo"
}

ticks() {
  grep -c '^tick$' "$repo/agent.marker" 2>/dev/null || printf '0\n'
}

@test "the loop makes exactly max_iterations turns and stops with exit 0" {
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    run "$GUBIA_BIN" run plan/plan.md 3
  [ "$status" -eq 0 ]
  [ "$(ticks)" -eq 3 ]
  # The stop is announced on stderr naming the ceiling, and says there
  # was no stop file: that is the datum that distinguishes this exit 0
  # from that of a finished plan.
  grep -q 'max_iterations reached (3)' <<<"$output"
  grep -q 'without a stop file' <<<"$output"
}

@test "max_iterations=1 invokes the agent exactly once" {
  # The edge case of `<=`: with `<` there would be no invocation.
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    run "$GUBIA_BIN" run plan/plan.md 1
  [ "$status" -eq 0 ]
  [ "$(ticks)" -eq 1 ]
}

@test "the counter numbers the logs of each turn and does not overwrite them" {
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    run "$GUBIA_BIN" run plan/plan.md 3
  [ "$status" -eq 0 ]
  # A counter that did not advance would write three times over `1.*`.
  [ -f .gubia/logs/1.out ]
  [ -f .gubia/logs/2.out ]
  [ -f .gubia/logs/3.out ]
  [ ! -e .gubia/logs/4.out ]
}

@test "the ceiling is not persisted: two consecutive invocations each spend their full quota" {
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    run "$GUBIA_BIN" run plan/plan.md 2
  [ "$status" -eq 0 ]
  [ "$(ticks)" -eq 2 ]
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    run "$GUBIA_BIN" run plan/plan.md 2
  [ "$status" -eq 0 ]
  [ "$(ticks)" -eq 4 ]
}

@test "the stop file cuts the loop before exhausting the ceiling" {
  # The ceiling is a limit, not a commitment: the other normal exit
  # still rules and stops on the first turn, without invoking the agent.
  printf 'parada\n' >plan/stop.md
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    run "$GUBIA_BIN" run plan/plan.md 5
  [ "$status" -eq 0 ]
  [ "$(ticks)" -eq 0 ]
  grep -q 'stop file present' <<<"$output"
  ! grep -q 'max_iterations reached' <<<"$output"
}

@test "the positional alias accepts the ceiling just like the subcommand" {
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    run "$GUBIA_BIN" plan/plan.md 2
  [ "$status" -eq 0 ]
  [ "$(ticks)" -eq 2 ]
}

@test "an invalid max_iterations dies with exit 2 without invoking the agent or taking the lock" {
  local malo
  for malo in 0 -1 abc 2.5 ' '; do
    rm -f "$repo/agent.marker"
    GUBIA_AGENTS_SH="$repo/config/agents.sh" \
      run "$GUBIA_BIN" run plan/plan.md "$malo"
    [ "$status" -eq 2 ]
    grep -q 'invalid max_iterations' <<<"$output"
    [ "$(ticks)" -eq 0 ]
    [ ! -e "$repo/.gubia/plan-plan.md.lock" ]
  done
}

@test "an absent catalog (neither local nor home) dies with exit 2 without taking the lock" {
  rm config/agents.sh
  HOME="$BATS_TEST_TMPDIR" run "$GUBIA_BIN" run plan/plan.md 1
  [ "$status" -eq 2 ]
  grep -q 'agent catalog not found' <<<"$output"
  [ ! -e "$repo/.gubia/plan-plan.md.lock" ]
}

@test "with no argument, the default ceiling is 500" {
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  run_resolve_max_iterations
  [ "$run_max_iterations" -eq 500 ]
  # Empty is the same as absent: it is what arrives from the `${3:-}` of
  # the dispatch when no third argument was written.
  run_max_iterations=
  run_resolve_max_iterations ''
  [ "$run_max_iterations" -eq 500 ]
}
