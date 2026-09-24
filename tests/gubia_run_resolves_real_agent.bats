#!/usr/bin/env bats

# E2e test of task 11 (last subtask: "Add a bats-core test (e2e with a
# fake CLI on the `PATH`) that verifies that one `gubia run` iteration
# invokes the real agent resolved by `model_index` within the active
# fallback list … instead of `agent_probe`, and that it preserves the
# order `wait` → `INTERRUPTED` flag → interpret rc and the 126/127 `die`
# without rotating").
#
# Where `gubia_run_max_iterations.bats` and
# `gubia_rotation_fallback_exhausted.bats` already test the whole loop
# with a single catalog agent, this suite adds what is missing: a catalog
# with TWO agents — the real one that `model_index` selects and
# `agent_probe`, which must stay silent — to show that
# `run_invoke_iteration` invokes the first and never the second; and,
# separately, that a 126/127 rc during that same e2e invocation dies with
# exit 2 without persisting any rotation in `state.env` (the unit
# evidence of that `die` already lives in `invoke_agent_rc_die.bats`;
# here it is observed through the whole engine, with `model_index`
# resolved in between).

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  bin="$repo/bin"
  mkdir -p "$bin" config plan
  printf '# Plan\n- [ ] [00. task](plan/00.md)\n' >plan/plan.md
  # Passthrough of `systemd-run`, first on the PATH: if the machine
  # running the suite really has it (`require_tools` detects it and
  # `invoke_prepare` wraps the invocation with it), the real 126/127 of
  # the agent CLI is masked by `systemd-run`'s own rc (note from
  # `invoke_agent_rc_die.bats`). This stub forwards the exec as-is after
  # the `--`, so the observed rc is still the agent CLI's, without
  # depending on whether the test machine has user systemd available.
  cat >"$bin/systemd-run" <<'CLI'
#!/usr/bin/env bash
args=("$@")
for i in "${!args[@]}"; do
  if [ "${args[$i]}" = '--' ]; then
    exec "${args[@]:$((i + 1))}"
  fi
done
exec "$@"
CLI
  chmod +x "$bin/systemd-run"
}

teardown() {
  cd /
  rm -rf "$repo"
}

run_gubia() {
  PATH="$bin:$PATH" GUBIA_AGENTS_SH="$repo/config/agents.sh" \
    run "$GUBIA_BIN" run plan/plan.md "$@"
}

# Catalog with `agent_claude` (what `model_index=0` of
# `GUBIA_FALLBACK_MEDIUM` — the default level of `state_defaults` —
# must resolve) and `agent_probe`, reachable by the catalog but which the
# loop must never select. Each one signs its own marker so that the
# absence of a signature is the proof that it was not invoked.
write_catalog() {
  local claude_cli="$1" probe_cli="$2"
  cat >config/agents.sh <<EOF
declare -rA GUBIA_MODELS=(
  [claude-medium]='claude fake-medium'
  [probe-medium]='probe fake-probe'
)
declare -ra GUBIA_FALLBACK_MEDIUM=(claude-medium)
agent_claude() {
  GUBIA_PROMPT_MODE='file'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=("$claude_cli")
  GUBIA_ENV=()
}
agent_probe() {
  GUBIA_PROMPT_MODE='stdin'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=("$probe_cli")
  GUBIA_ENV=()
}
EOF
}

@test "one gubia run iteration invokes the real agent resolved by model_index, never agent_probe" {
  cat >"$bin/claude-cli" <<CLI
#!/usr/bin/env bash
printf 'claude\n' >>'$repo/claude.marker'
exit 0
CLI
  chmod +x "$bin/claude-cli"
  cat >"$bin/probe-cli" <<CLI
#!/usr/bin/env bash
printf 'probe\n' >>'$repo/probe.marker'
exit 0
CLI
  chmod +x "$bin/probe-cli"
  write_catalog "$bin/claude-cli" "$bin/probe-cli"

  # Without a prior `.gubia/state.env`: `state_defaults` leaves effort_level=medium
  # and model_index=0, which is exactly the `claude-medium` entry of the fallback.
  run_gubia 1
  [ "$status" -eq 0 ]

  [ "$(cat "$repo/claude.marker" 2>/dev/null)" = 'claude' ]
  [ ! -e "$repo/probe.marker" ]
}

@test "a 127 rc during the iteration dies with exit 2 without rotating model_index" {
  # `claude-absent` does not exist: exit 127 from `wait`, captured BEFORE
  # the task 06 rotation can touch `model_index`.
  write_catalog "$bin/claude-absent" "$bin/probe-cli"

  run_gubia 3
  [ "$status" -eq 2 ]
  [[ "$output" == *127* ]]

  # `model_index` stays at 0: the `die` cuts before the decision to
  # rotate (subtask of task 06) gets to run.
  grep -q '^model_index=0$' "$repo/.gubia/state.env"
  [ ! -e "$repo/probe.marker" ]
}

@test "a 126 rc during the iteration dies with exit 2 without rotating model_index" {
  # CLI present but without execute permission: exit 126.
  cat >"$bin/claude-no-exec" <<'CLI'
#!/usr/bin/env bash
exit 0
CLI
  chmod -x "$bin/claude-no-exec"
  write_catalog "$bin/claude-no-exec" "$bin/probe-cli"

  run_gubia 3
  [ "$status" -eq 2 ]
  [[ "$output" == *126* ]]

  grep -q '^model_index=0$' "$repo/.gubia/state.env"
  [ ! -e "$repo/probe.marker" ]
}
