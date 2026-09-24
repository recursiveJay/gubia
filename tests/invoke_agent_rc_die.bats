#!/usr/bin/env bats

# Test of exit codes 126/127 (plan/05.md, subtask "Add a bats-core test
# with a fake CLI in the `PATH` that verifies that exit codes 126 and
# 127 cause an immediate `die` instead of rotation").
#
# `invoke_rc_die` does a real `exit 2` (not `return`): to observe it
# without killing the bats process, each case runs in a separate bash
# subprocess that sources `gubia`/`config/agents.sh`, invokes the fake
# agent and, if `invoke_agent` were to return control (it should not:
# `die` cuts it short first), betrays it by printing its rc — so a future
# failure that turned the `die` into a `return` shows up as a broken
# assertion, not as silent output with the wrong status.
#
# The 127 (missing CLI) and the 126 (CLI present but not executable) are
# produced without the `systemd-run` wrapper — the `invoke_rc_die` note
# documents that with the wrapper in place it is `systemd-run` that
# aborts first with its own rc 1, so these two cases are only observable
# in the direct launch with `setsid` (without `systemd-run` in the PATH).

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"
AGENTS_SH="${BATS_TEST_DIRNAME}/../config/agents.sh"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  bin="$repo/bin"
  mkdir -p "$bin" plan
  cat >plan/plan.md <<'PLAN'
# Plan
- [ ] [00. task](plan/00.md)
PLAN
}

# Runs invoke_agent against the indicated fake CLI, in its own bash
# subprocess: if invoke_rc_die fires its `exit 2`, that `exit` ends the
# subprocess (not bats), and `run` collects its status and output.
run_invoke() {
  local argv_path="$1"
  cat >"$repo/run_invoke.sh" <<EOF
set -u
# shellcheck source=/dev/null
source "$GUBIA_BIN"
# shellcheck source=/dev/null
source "$AGENTS_SH"
agent_fake() {
  GUBIA_PROMPT_MODE='file'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=("$argv_path")
  GUBIA_ENV=()
}
run_resolve_plan plan/plan.md
run_acquire_lock
run_export_env
mkdir -p .gubia/logs
invoke_agent agent_fake m1 medium true 1
printf 'invoke_agent returned without dying: rc=%d\n' "\$?"
EOF
  run bash "$repo/run_invoke.sh"
}

@test "exit 127 (missing CLI): immediate die with exit 2, never rotation" {
  run_invoke "$bin/nonexistent-cli"
  [ "$status" -eq 2 ]
  [[ "$output" == *127* ]]
  [[ "$output" != *'invoke_agent returned'* ]]
}

@test "exit 126 (non-executable CLI): immediate die with exit 2, never rotation" {
  cat >"$bin/non-executable" <<'CLI'
#!/usr/bin/env bash
exit 0
CLI
  chmod -x "$bin/non-executable"
  run_invoke "$bin/non-executable"
  [ "$status" -eq 2 ]
  [[ "$output" == *126* ]]
  [[ "$output" != *'invoke_agent returned'* ]]
}
