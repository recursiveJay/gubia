#!/usr/bin/env bats

# The active agent resolution (task 11) is tested against an isolated
# catalog located via PATH. This way the real catalog is not sourced nor
# can any of its CLIs be invoked: only the table
# GUBIA_FALLBACK_<level> -> GUBIA_MODELS -> agent_<name> is exercised.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  bin="$repo/bin"
  mkdir -p "$bin"
  cd "$repo" || return
}

teardown() {
  cd /
  rm -rf "$repo"
}

write_catalog() {
  cat >"$bin/agents.sh" <<'AGENTS'
declare -A GUBIA_MODELS=(
  [codex-medium]='codex gpt-test-medium'
  [omp-medium]='omp deepseek-test'
)
declare -a GUBIA_FALLBACK_LOW=(codex-medium)
declare -a GUBIA_FALLBACK_MEDIUM=(codex-medium omp-medium)
declare -a GUBIA_FALLBACK_HIGH=(omp-medium)

agent_codex() { :; }
agent_omp() { :; }
AGENTS
}

# Runs the resolution in another bash: the paths that diagnose a broken
# catalog end with `exit 2`, so they cannot be called with bats' `run`
# after sourcing the engine in the same test process.
resolve() {
  # shellcheck disable=SC2016 # $1/$2 expand inside the child bash.
  run env PATH="$bin:$PATH" GUBIA_BIN="$GUBIA_BIN" bash -c '
    source "$GUBIA_BIN"
    source agents.sh
    run_resolve_agent "$1" "$2"
    printf "%s|%s\n" "$run_resolved_agent_fn" "$run_resolved_model"
  ' -- "$1" "$2"
}

@test "resolves the active entry to the correct agent function and model" {
  write_catalog

  resolve medium 1

  [ "$status" -eq 0 ]
  [ "$output" = 'agent_omp|deepseek-test' ]
}

@test "dies with exit 2 if the active entry does not exist in GUBIA_MODELS" {
  write_catalog
  cat >>"$bin/agents.sh" <<'AGENTS'
GUBIA_FALLBACK_LOW=(missing-low)
AGENTS

  resolve low 0

  [ "$status" -eq 2 ]
  grep -q 'model missing-low from the active fallback list is not defined in GUBIA_MODELS' <<<"$output"
}

@test "dies with exit 2 if the active entry has no associated agent function" {
  write_catalog
  cat >>"$bin/agents.sh" <<'AGENTS'
GUBIA_MODELS[ghost-medium]='ghost no-cli'
GUBIA_FALLBACK_HIGH=(ghost-medium)
AGENTS

  resolve high 0

  [ "$status" -eq 2 ]
  grep -q 'model ghost-medium requires agent_ghost' <<<"$output"
}
