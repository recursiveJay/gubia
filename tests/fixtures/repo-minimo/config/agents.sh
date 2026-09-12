#!/usr/bin/env bash
#
# agents.sh — agent catalog of the `repo-minimo` fixture (task 10).
#
# Minimal copy of the pattern of the real repo's `config/agents.sh`, trimmed
# to what the fixture's e2e tests need: the four agent functions (so that
# `config_validate_agent_functions` passes), the model/fallback arrays, and
# an `agent_probe` that points at the fixture's fake CLI (`fake-cli.sh`) —
# the current loop invokes it to drain the test plan.
#
# It is sourced with `GUBIA_AGENTS_SH` pointing here, from the directory of
# the temporary repo the test copies the fixture into; `fake-cli.sh` is
# referenced by absolute path derived from this very file
# (BATS_TEST_DIRNAME does not exist here), just like the real repo's probe
# does with `scripts/agent-probe.sh`.
#
# The fixture's real functions receive their prompt via file; the probe
# keeps stdin, just like the real catalog's. The fake CLI accepts both
# transports and leaves its output on stdout.
#
# SC2034: the arrays are consumed after `source` from the engine, not in
# this file.
# shellcheck disable=SC2034
declare -rA GUBIA_MODELS=(
    [codex-low]="codex fake-low"
    [claude-medium]="claude fake-medium"
    [omp-medium]="omp fake-medium"
    [devin-medium]="devin fake-medium"
)

# shellcheck disable=SC2034
declare -ra GUBIA_FALLBACK_LOW=(codex-low)
# shellcheck disable=SC2034
declare -ra GUBIA_FALLBACK_MEDIUM=(
    claude-medium
    omp-medium
    devin-medium
)
# shellcheck disable=SC2034
declare -ra GUBIA_FALLBACK_HIGH=(claude-medium)
# A real CLI does not exist on the test machine: the fixture's world is the
# fake, so the four build the same invocation. The model/effort/thinking
# arguments are decorative, just like in the real repo's probe.
agent_codex()  { _fixture_agent; }
agent_claude() { _fixture_agent; }
agent_omp()    { _fixture_agent; }
agent_devin()  { _fixture_agent; }

agent_probe() {
  if (( $# < 3 )); then
    printf 'agent_probe: usage: agent_probe <model> <effort> <thinking>\n' >&2
    return 2
  fi
  GUBIA_PROMPT_MODE='stdin'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=("${config_fake_cli_abs}")
  GUBIA_ENV=()
}

_fixture_agent() {
  GUBIA_PROMPT_MODE='file'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=("${config_fake_cli_abs}")
  GUBIA_ENV=()
}

# Absolute path of the fake CLI, derived from the location of this file at
# source time (not from the cwd of the sourcing process), with the same
# technique as the real catalog's `config_probe_abs`.
config_fake_abs_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
config_fake_cli_abs="${config_fake_abs_dir}/../fake-cli.sh"
# Guard for slash-less source (`source agents.sh`): `%/*` trims nothing and
# would leave `agents.sh` as if it were the directory.
[[ "$config_fake_cli_abs" == */fake-cli.sh ]] || {
  printf 'agents.sh: cannot derive the path of fake-cli.sh from %s\n' \
    "${BASH_SOURCE[0]}" >&2
  exit 1
}
