#!/usr/bin/env bats

# The catalog's real functions have deliberately different arities. This
# evidence replaces them with stubs to check the engine's wiring without
# running any CLI or depending on credentials.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  bin="$repo/bin"
  mkdir -p "$bin" "$repo/plan"
  cd "$repo" || return
  cat >plan/plan.md <<'PLAN'
# Plan
- [ ] [00. task]
PLAN

  # The fake codex agent writes through its console_output argument; any
  # stdout of its own must be discarded when normalizing the observation.
  cat >"$bin/write-console" <<'CLI'
#!/usr/bin/env bash
printf 'observation-from-console\n' >"$1"
printf 'stdout-that-is-not-the-observation\n'
CLI
  chmod +x "$bin/write-console"

  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  run_resolve_plan plan/plan.md
  run_acquire_lock
  run_export_env
  mkdir -p .gubia/logs

  agent_codex() {
    codex_args=("$@")
    GUBIA_PROMPT_MODE='stdin'
    GUBIA_OUTPUT_MODE='file'
    GUBIA_ARGV=(codex-cli "$4")
    GUBIA_ENV=()
  }
  agent_claude() {
    claude_args=("$@")
    GUBIA_PROMPT_MODE='stdin'
    GUBIA_OUTPUT_MODE='stdout'
    GUBIA_ARGV=(claude-cli)
    GUBIA_ENV=()
  }
  agent_omp() {
    omp_args=("$@")
    GUBIA_PROMPT_MODE='file'
    GUBIA_OUTPUT_MODE='stdout'
    GUBIA_ARGV=(omp-cli "$4")
    GUBIA_ENV=()
  }
  agent_devin() {
    devin_args=("$@")
    GUBIA_PROMPT_MODE='file'
    GUBIA_OUTPUT_MODE='stdout'
    GUBIA_ARGV=(devin-cli "$2")
    GUBIA_ENV=()
  }
}

teardown() {
  cd /
  rm -rf "$repo"
}

@test "invoke_prepare respects the real signatures and does not add the prompt to GUBIA_ARGV" {
  invoke_prepare agent_codex codex-model medium true 21
  [ "${#codex_args[@]}" -eq 4 ]
  [ "${codex_args[3]}" = "$repo/.gubia/logs/21.console" ]
  [ "${GUBIA_ARGV[*]}" = "codex-cli $repo/.gubia/logs/21.console" ]

  invoke_prepare agent_claude claude-model medium true 22
  [ "${#claude_args[@]}" -eq 3 ]
  [ "${claude_args[*]}" = 'claude-model medium true' ]
  [ "${GUBIA_ARGV[*]}" = 'claude-cli' ]

  invoke_prepare agent_omp omp-model medium true 23
  [ "${#omp_args[@]}" -eq 4 ]
  [ "${omp_args[3]}" = "$repo/.gubia/logs/23.prompt" ]
  [ "${GUBIA_ARGV[*]}" = "omp-cli $repo/.gubia/logs/23.prompt" ]

  invoke_prepare agent_devin devin-model medium true 24
  [ "${#devin_args[@]}" -eq 2 ]
  [ "${devin_args[1]}" = "$repo/.gubia/logs/24.prompt" ]
  [ "${GUBIA_ARGV[*]}" = "devin-cli $repo/.gubia/logs/24.prompt" ]
}

@test "invoke_agent normalizes console_output as the .out observation" {
  # This stub keeps the same signature as codex, but prepares a fake CLI
  # that writes to console_output and also emits stdout to demonstrate
  # the origin.
  agent_codex() {
    codex_args=("$@")
    GUBIA_PROMPT_MODE='stdin'
    GUBIA_OUTPUT_MODE='file'
    GUBIA_ARGV=("$bin/write-console" "$4")
    GUBIA_ENV=()
  }

  invoke_agent agent_codex codex-model medium true 25

  [ "${codex_args[3]}" = "$repo/.gubia/logs/25.console" ]
  [ "$(<.gubia/logs/25.out)" = 'observation-from-console' ]
  ! grep -q 'stdout-that-is-not-the-observation' .gubia/logs/25.out
}

@test "invoke_agent leaves .out empty (does not fail) if the agent dies before writing console_output" {
  # The CLI fails before materializing its console file: normalization
  # must not attempt a `cat` of a nonexistent path nor mask the agent's
  # real rc with an artificial failure of `cat` itself.
  cat >"$bin/fail-before-console" <<'CLI'
#!/usr/bin/env bash
exit 3
CLI
  chmod +x "$bin/fail-before-console"

  agent_codex() {
    codex_args=("$@")
    GUBIA_PROMPT_MODE='stdin'
    GUBIA_OUTPUT_MODE='file'
    GUBIA_ARGV=("$bin/fail-before-console")
    GUBIA_ENV=()
  }

  run invoke_agent agent_codex codex-model medium true 26
  [ "$status" -eq 3 ]
  [ ! -e "$repo/.gubia/logs/26.console" ]
  [ -e "$repo/.gubia/logs/26.out" ]
  [ -z "$(<.gubia/logs/26.out)" ]
}
