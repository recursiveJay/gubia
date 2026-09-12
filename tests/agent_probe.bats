#!/usr/bin/env bats

# Test of agent_probe (plan/04.md, subtask "[create evidence]"): the
# engine's test agent, with which the invocation is verified without
# touching any real CLI.
#
# What this file pins down is the agent itself — that it fulfills the
# same contract as the real agents in `agents.sh` and that its
# executable is invocable from any cwd. That `gubia run` actually invokes
# it and the dump comes out right is pinned down by `run_export_env.bats`
# and `run_prompt.bats` end to end.

AGENTS_SH="${BATS_TEST_DIRNAME}/../config/agents.sh"

setup() {
  # shellcheck source=/dev/null
  source "$AGENTS_SH"
}

@test "agent_probe: transport via stdin, output to stdout and no own env" {
  agent_probe probe medium true

  [ "$GUBIA_PROMPT_MODE" = "stdin" ]
  [ "$GUBIA_OUTPUT_MODE" = "stdout" ]
  # The binary takes no options: argv is only the executable.
  [ "${#GUBIA_ARGV[@]}" -eq 1 ]
  [ "${#GUBIA_ENV[@]}" -eq 0 ]
}

# The argv is executed later, in a cwd the function does not control:
# a relative path here would work from the repo root and fail from
# anywhere else.
@test "agent_probe: the executable is an absolute and executable path" {
  agent_probe probe medium true

  [[ "${GUBIA_ARGV[0]}" == /* ]]
  [ -x "${GUBIA_ARGV[0]}" ]
}

@test "agent_probe: the executable path does not depend on the sourcing cwd" {
  local desde_raiz="${GUBIA_ARGV[0]:-}"
  agent_probe probe medium true
  desde_raiz="${GUBIA_ARGV[0]}"

  cd "$BATS_TEST_TMPDIR"
  # shellcheck source=/dev/null
  source "$AGENTS_SH"
  agent_probe probe medium true

  [ "${GUBIA_ARGV[0]}" = "$desde_raiz" ]
}

@test "sourcing the catalog without scripts/ next to config/ does not abort (the probe is lazy)" {
  mkdir -p "$BATS_TEST_TMPDIR/solo-config/config"
  cp "$AGENTS_SH" "$BATS_TEST_TMPDIR/solo-config/config/agents.sh"

  cd "$BATS_TEST_TMPDIR/solo-config"
  # `set -e` reproduces the engine's context: before, the `cd` to
  # `../scripts` of the top-level `config_probe_abs` aborted the whole
  # source and took the real fallback lists with it.
  run bash -c 'set -euo pipefail; source config/agents.sh; declare -p GUBIA_FALLBACK_MEDIUM'
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex-medium"* ]]
}

@test "agent_probe: incorrect usage (fewer than 3 arguments) returns 2" {
  run agent_probe probe medium
  [ "$status" -eq 2 ]
}

# The agent runs no real external process: dump and exit. It is checked
# by invoking its executable exactly as `agent_probe` left it.
@test "agent_probe: the executable dumps env and prompt, and exits 0" {
  agent_probe probe medium true
  local dump="${BATS_TEST_TMPDIR}/dump.txt"

  GUBIA_PROBE_DUMP="$dump" MARCA_DE_ENTORNO=presente \
    run bash -c 'printf "PROMPT_DE_PRUEBA\n" | "$1"' _ "${GUBIA_ARGV[0]}"
  [ "$status" -eq 0 ]

  grep -qx '===== env =====' "$dump"
  grep -qx 'MARCA_DE_ENTORNO=presente' "$dump"
  [ "$(sed '1,/^===== prompt =====$/d' "$dump")" = "PROMPT_DE_PRUEBA" ]
}
