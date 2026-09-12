#!/usr/bin/env bats

# Test of the export of GUBIA_ROOT and GUBIA_PLAN into the environment
# of the agent's child process (plan/04.md: "Implement the export of
# `GUBIA_ROOT` and `GUBIA_PLAN` in the environment of the agent's child
# process").
#
# The `run_` module is sourced from the script (BASH_SOURCE guard): the
# test's cwd is set, `run_resolve_plan` is called and then
# `run_export_env`, and the exported environment is observed from a real
# child process (`env`), which is exactly how the agent receives it. The
# invocation layer (`invoke_`) arrives with its own subtask; what this
# test pins down is that what that layer inherits is already well formed.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
}

@test "exports absolute GUBIA_ROOT and GUBIA_PLAN relative to the root" {
  mkdir -p plan
  touch plan/plan.md
  run_resolve_plan plan/plan.md
  run_export_env
  [ "$GUBIA_ROOT" = "$PWD" ]
  [ "$GUBIA_PLAN" = "plan/plan.md" ]
}

@test "a real child process sees both variables with the same values" {
  mkdir -p plan
  touch plan/plan.md
  run_resolve_plan plan/plan.md
  run_export_env
  run env bash -c 'printf "root:%s\nplan:%s\n" "$GUBIA_ROOT" "$GUBIA_PLAN"'
  [ "$status" -eq 0 ]
  grep -qx "root:$PWD" <<<"$output"
  grep -qx "plan:plan/plan.md" <<<"$output"
}

@test "a plan with .. that stays inside exports the canonical relative form" {
  mkdir -p plan
  touch plan/plan.md
  run_resolve_plan plan/../plan/plan.md
  run_export_env
  [ "$GUBIA_PLAN" = "plan/plan.md" ]
}

@test "exporting before resolving the plan dies with exit 2 and its own message" {
  run run_export_env
  [ "$status" -eq 2 ]
  grep -q 'before resolving the plan' <<<"$output"
}

@test "neither variable enters state.env" {
  mkdir -p plan
  touch plan/plan.md
  run_resolve_plan plan/plan.md
  run_export_env
  state_ensure
  ! grep -q 'GUBIA_ROOT\|GUBIA_PLAN' .gubia/state.env
}
# End to end: the above pins the shape of the two variables; this pins
# that the `run` subcommand actually delivers them to the agent's child
# process. The active agent is the catalog's `agent_probe`, which dumps
# its `env` to a file: the dump is the direct observation of the
# environment the child receives, not an inference about the engine's.
@test "gubia run delivers both variables to the child process environment" {
  mkdir -p plan config
  printf '# plan\n- [ ] [00. task](plan/00.md)\n' >plan/plan.md
  # Isolated catalog that resolves the default active entry to the real
  # `agent_probe`: it is the one that dumps its `env` to a file.
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
  # `max_iterations=1`: the probe exits 0 and does not create a stop
  # file, so without a cap the engine would spin the default 500 turns.
  # A single iteration is enough for what this test observes.
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
  GUBIA_PROBE_DUMP="${repo}/dump.txt" \
    run "$GUBIA_BIN" run plan/plan.md 1
  [ "$status" -eq 0 ]
  [ -f "${repo}/dump.txt" ]
  local env_section
  env_section="$(sed -n '/^===== env =====$/,/^===== prompt =====$/p' "${repo}/dump.txt")"
  grep -qx "GUBIA_ROOT=${repo}" <<<"$env_section"
  grep -qx "GUBIA_PLAN=plan/plan.md" <<<"$env_section"
}

@test "a plan outside the root dies before invoking the agent" {
  mkdir -p plan
  printf '# plan\n- [ ] [00. task](plan/00.md)\n' >plan/plan.md
  local fuera="${BATS_TEST_TMPDIR}/plan-fuera.md"
  cp plan/plan.md "$fuera"
  GUBIA_AGENTS_SH="${BATS_TEST_DIRNAME}/../config/agents.sh" \
  GUBIA_PROBE_DUMP="${repo}/dump.txt" \
    run "$GUBIA_BIN" run "$fuera"
  [ "$status" -ne 0 ]
  [ ! -e "${repo}/dump.txt" ]
}
