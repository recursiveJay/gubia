#!/usr/bin/env bats

# Test of the process group teardown (plan/05.md, subtask "Add a
# bats-core test with a fake CLI in the `PATH` that verifies that the
# teardown of an iteration kills the whole process group without
# leaving orphans").
#
# The fake CLI does not just terminate: before exiting it launches a
# grandchild in the background (`sleep` that ignores TERM) WITHOUT its
# own `setsid`, so the grandchild inherits the same PGID that
# `invoke_agent` saved from the CLI. The parent CLI terminates right
# away (rc 0), but the grandchild stays alive — the real case the spec
# fears: an MCP or a `git` that survives the agent and would keep
# writing to the plan during the next iteration if it were not killed
# by GROUP.
#
# The grandchild ignores TERM on purpose: it forces the escalation of
# `invoke_kill_group` up to the final `KILL`, not just the first `TERM`
# that a well-behaved process would already have handled.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"
AGENTS_SH="${BATS_TEST_DIRNAME}/../config/agents.sh"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  bin="$repo/bin"
  mkdir -p "$bin" plan
  cat >"$bin/fake-cli" <<'CLI'
#!/usr/bin/env bash
# Grandchild that ignores TERM, in the SAME process group as this CLI
# (without its own setsid): only a KILL to the whole group kills it.
(
  trap '' TERM
  printf '%d\n' "$$" >"$GRANDCHILD_MARKER"
  sleep 30
) &
disown
# The parent CLI terminates right away; the grandchild is orphaned from
# it, but stays in the group that invoke_agent saved as PGID.
exit 0
CLI
  chmod +x "$bin/fake-cli"
  PATH="$bin:$PATH"
  cat >plan/plan.md <<'PLAN'
# Plan
- [ ] [00. task](plan/00.md)
PLAN
}

fake_catalog() {
  agent_fake() {
    GUBIA_PROMPT_MODE='file'
    GUBIA_OUTPUT_MODE='stdout'
    GUBIA_ARGV=("$bin/fake-cli")
    GUBIA_ENV=("GRANDCHILD_MARKER=$repo/grandchild.pid")
  }
}

@test "the iteration teardown kills the whole group, leaving no orphans" {
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  # shellcheck source=/dev/null
  source "$AGENTS_SH"
  fake_catalog
  # Short grace (whole seconds: `invoke_term_grace` enters bash
  # arithmetic): the grandchild ignores TERM on purpose, so the test
  # does not need to wait the default grace period until the KILL.
  invoke_term_grace=1
  run_resolve_plan plan/plan.md
  run_acquire_lock
  run_export_env
  mkdir -p .gubia/logs

  rc=0
  invoke_agent agent_fake m1 medium true 3 || rc=$?
  [ "$rc" -eq 0 ]

  # The grandchild announced itself before the parent CLI terminated.
  local grandchild
  for _i in $(seq 1 50); do
    [[ -s "$repo/grandchild.pid" ]] && break
    sleep 0.05
  done
  grandchild="$(cat "$repo/grandchild.pid")"
  [ -n "$grandchild" ]

  # The invoke_agent teardown already ran (invoke_agent returned): the
  # grandchild, which ignores TERM, could only have died from the final
  # KILL to the group — it never stayed alive as an orphan after the
  # iteration.
  ! kill -0 "$grandchild" 2>/dev/null
}
