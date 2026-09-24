#!/usr/bin/env bats

# Test of the engine's EXIT trap (plan/05.md, subtask "[create
# evidence] Add a bats-core test that verifies the EXIT trap captures
# `$?` in its first line, never deletes the lockfile, and has a
# reentrancy guard").
#
# Two complementary tests, same split as the SIGINT trap test
# (invoke_agent_sigint_trap.bats):
#
# 1. End to end, with the REAL engine (`gubia run`): the EXIT trap
#    writes the captured rc to a marker BEFORE anything else that
#    could clobber it, and the test observes both that rc and the real
#    process state (exit code seen by the parent, lockfile still on
#    disk). The non-zero rc with which the engine dies is the 3 of
#    `fallback-exhausted`: the fake agent returns exit 7 and the
#    catalog declares a fallback list of ONE model, so the rotation
#    returns to the index of the first failure and the loop aborts
#    after that single iteration. The rc captured by the trap must be
#    exactly that 3 — capturing anything else (0 after the guard, a 2
#    from an `[[ ]]`) would be the bug the spec forbids ("The EXIT
#    trap captures `$?` in its first line").
#
#    Why the agent's 7 is no longer observed: since `cmd_run` iterates,
#    the agent's exit code is not an output of the engine — a rc ≠ 0
#    rotates model and keeps iterating. The only non-zero-rc deaths of
#    the loop are `fallback-exhausted` (3), lock contention (1) and
#    invalid configuration (2); this test uses the first because it is
#    the one that happens AFTER a real invocation, with the trap
#    already installed and an agent already launched.
#
# 2. Unit, on the sourced script: with the reentrancy guard active
#    (`invoke_exit_trap_active`), `invoke_trap_exit` is a no-op — it
#    neither closes the group of a live agent nor re-emits exit. It is
#    the direct observation of the guard: without it, the second entry
#    would close the group again and this test would die with the exit
#    of the first pass.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  export GUBIA_EXIT_TRAP_MARKER="$repo/exit-trap.marker"
  bin="$repo/bin"
  mkdir -p "$bin" config plan
  # Agent that dies with exit 7 and announces its pid in the marker: it
  # is the non-zero rc the EXIT trap must capture in its first line,
  # and the process on which it is verified that the trap does not
  # repeat the close.
  cat >"$bin/exit7-cli" <<'CLI'
#!/usr/bin/env bash
printf 'agent-pid=%d\n' $$ >"$AGENT_MARKER"
exit 7
CLI
  chmod +x "$bin/exit7-cli"
  # Sleeping agent for the guard test: the victim must still be ALIVE
  # when returning from the protected handler, and that requires a
  # process that does not die on its own (the exit7-cli above already
  # left with its exit 7).
  cat >"$bin/sleep-cli" <<'CLI'
#!/usr/bin/env bash
printf 'agent-pid=%d\n' $$ >"$AGENT_MARKER"
sleep 30
CLI
  chmod +x "$bin/sleep-cli"
  PATH="$bin:$PATH"
  # Fake catalog with file transport: same contract as `agent_probe`
  # from config/agents.sh.
  # The fallback list of the default level (medium) has a single model:
  # with it, the agent's exit 7 marks the streak, rotates to itself and
  # `run_streak_check` aborts with `fallback-exhausted` (exit 3) on the
  # first loop turn — which is the non-zero-rc death this test needs to
  # observe.
  cat >config/agents.sh <<EOF
declare -rA GUBIA_MODELS=([uno]='claude fake')
declare -ra GUBIA_FALLBACK_MEDIUM=(uno)
agent_claude() {
  GUBIA_PROMPT_MODE='file'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=("$bin/exit7-cli")
  GUBIA_ENV=("AGENT_MARKER=$repo/agent.marker")
}
EOF
  cat >plan/plan.md <<'PLAN'
# Plan
- [ ] [00. task](plan/00.md)
PLAN
}

teardown() {
  # The temp repo goes away with everything inside it: lockfile and
  # logs included. `cd` so that mktemp -d can unlink it.
  cd /
  rm -rf "$repo"
}

@test "gubia run: the EXIT trap captures the real rc, does not delete the lockfile, and re-emits the exit" {
  # Minimal wrapper instead of `run`: the engine dies with exit 3
  # (`fallback-exhausted` after the agent's exit 7), which bats' `run`
  # would treat as a test failure before anything could be inspected.
  set +e
  "$GUBIA_BIN" run plan/plan.md >"$repo/run.out" 2>"$repo/run.err"
  engine_rc=$?
  set -e

  # The engine re-emits the captured rc: an EXIT trap that did not do
  # `exit "$rc"` would let through the rc of the trap's last command
  # (here the guard `[[ -z … ]]`, exit 0) and the parent would see 0
  # for a real loop abort.
  [ "$engine_rc" -eq 3 ]

  # The lockfile stays on disk after the process exits: the trap does
  # not delete it ("never delete the lockfile in the trap").
  [ -f "$repo/.gubia/plan-plan.md.lock" ]

  # The rc capture is observable: the trap signed its capture in the
  # marker BEFORE touching anything else (first line of the body). The
  # expected value is the 3 of the abort — neither the 1 of the flock,
  # nor the 0 of a later trap command.
  [ -f "$repo/exit-trap.marker" ]
  grep -q '^exit-trap rc=3$' "$repo/exit-trap.marker"
  # The agent died exactly once from the normal close of the iteration
  # (invoke_agent), not twice: the EXIT trap with the group already
  # dead is a no-op (invoke_kill_group fails the TERM and returns).
  [ "$(grep -c '^terms=' "$repo/agent.marker" 2>/dev/null)" -eq 0 ]
}

@test "reentrancy guard: with invoke_exit_trap_active set, invoke_trap_exit is a no-op" {
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  AGENT_MARKER="$repo/guard.marker"
  export AGENT_MARKER
  # Real victim in its own session group (same fake CLI from the PATH),
  # alive when entering the handler: without the guard, the second
  # entry would close it again.
  setsid "$bin/sleep-cli" >/dev/null 2>&1 &
  local victim=""
  local _i
  for _i in $(seq 1 100); do
    if [[ -s "$AGENT_MARKER" ]]; then
      victim="$(sed -n 's/^agent-pid=\([0-9]*\)$/\1/p' "$AGENT_MARKER")"
      [[ -n "$victim" ]] && break
    fi
    sleep 0.05
  done
  [[ -n "$victim" ]]
  kill -0 "$victim"

  # Module state "the trap already ran once": this is how the guard
  # finds a hypothetical second entry by any path.
  invoke_exit_trap_active=yes
  invoke_agent_pgid="$victim"

  # No prefixed pending state: bats and its ERR trap fight with the
  # `(exit N)` under `set -e` (the SIGINT test does not need it and
  # neither does this one). The no-op is observed by what does NOT
  # happen: this test stays alive (the `exit "$rc"` of the first pass
  # would have killed it), the victim stays alive and there is no
  # signature in the marker.
  invoke_trap_exit
  rc=$?
  [ "$rc" -eq 0 ]

  # Total no-op: the victim stays alive (without a second group close)
  # and with no capture signature in the trap's marker.
  kill -0 "$victim" 2>/dev/null
  ! grep -q '^exit-trap rc=' "$repo/exit-trap.marker" 2>/dev/null

  # Victim cleanup (same close as the SIGINT test).
  kill -TERM -- -"$victim" 2>/dev/null || true
  wait "$victim" 2>/dev/null || true
}
