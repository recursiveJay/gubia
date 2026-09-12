#!/usr/bin/env bats

# Test of the engine's SIGINT trap (plan/05.md, subtask "[create
# evidence] Add a bats-core test that sends `SIGINT` to the engine
# process during an invocation and verifies that the trap re-raises the
# signal (`trap - INT; kill -INT "$$"`) with a reentrancy guard").
#
# Two complementary tests:
#
# 1. End to end, with the REAL engine (`gubia run`): a python3 parent
#    launches the engine with a sleeping agent in the `PATH`, waits for
#    the invocation to be underway (the agent announces its pid in a
#    marker) and sends it SIGINT. The parent observes with raw
#    `waitpid`, not with bash's `$?`, because death BY SIGNAL is the
#    only thing that distinguishes the re-raise from the `exit 130`
#    that the spec forbids ("The signal trap re-raises the signal …
#    instead of `exit 130`, so that the parent can distinguish how the
#    process died"): bash's `wait` collapses both cases to 130, while
#    `waitpid` exposes WIFSIGNALED+WTERMSIG=2 (death BY SIGINT) against
#    WIFEXITED+WEXITSTATUS=130 (clean exit). Remaining observables: the
#    agent received exactly one TERM (the trap closed its group; the
#    `setsid` put it in ANOTHER session, so no one but the engine could
#    sign the signal to it), no live process remains from its group,
#    and the lockfile stays in place ("never delete the lockfile in the
#    trap").
#
# 2. Unit, on the sourced script: with the reentrancy guard active
#    (`invoke_int_trap_active`), `invoke_trap_int` is a no-op — it
#    neither sets `invoke_interrupted` nor touches the group of a live
#    agent. It is the direct observation of the guard: without it, the
#    second entry would close the group again and re-raise the signal,
#    and this test would die with the SIGINT itself.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  bin="$repo/bin"
  mkdir -p "$bin" config plan
  # systemd-run passthrough: `memory_max` comes from the state by
  # default (8G), so the engine invocation runs with the same
  # production wrapper (`setsid systemd-run … -- agent`) instead of the
  # unlimited fallback, without depending on whether the host machine
  # has systemd-run.
  cat >"$bin/systemd-run" <<'CLI'
#!/usr/bin/env bash
while (( $# )); do
  if [[ "$1" == -- ]]; then
    shift
    exec "$@"
  fi
  shift
done
printf 'fake systemd-run: missing the -- of the command\n' >&2
exit 125
CLI
  # Sleeping agent: announces its pid (the group's — the engine launches
  # it with setsid, and PID == PGID == SID) and counts in the marker the
  # TERMs it receives, so as to be able to assert that the group close
  # came from the trap and exactly once.
  cat >"$bin/sleep-cli" <<'CLI'
#!/usr/bin/env bash
terms=0
trap 'terms=$((terms+1)); printf "terms=%d\n" "$terms" >>"$AGENT_MARKER"; exit 0' TERM
printf 'agent-pid=%d\n' $$ >"$AGENT_MARKER"
sleep 30
CLI
  chmod +x "$bin/systemd-run" "$bin/sleep-cli"
  PATH="$bin:$PATH"
  # Fake catalog with stdin transport: same contract as `agent_probe`
  # from config/agents.sh, but with the sleeping agent instead of the
  # immediate dump of the real probe (the signal has to catch the engine
  # waiting INSIDE the invocation).
  cat >config/agents.sh <<EOF
declare -rA GUBIA_MODELS=([claude-test]='claude fake')
declare -ra GUBIA_FALLBACK_LOW=(claude-test)
declare -ra GUBIA_FALLBACK_MEDIUM=(claude-test)
declare -ra GUBIA_FALLBACK_HIGH=(claude-test)
agent_claude() {
  GUBIA_PROMPT_MODE='stdin'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=("$bin/sleep-cli")
  GUBIA_ENV=("AGENT_MARKER=$repo/agent.marker")
}
EOF
  printf '# Plan\n- [ ] [00. task](plan/00.md)\n' >plan/plan.md
  # Observer parent. Besides the raw `waitpid` (see header), it uses
  # /proc/<pid>/stat for the agent polling because the engine dies
  # without reaping it: it stays a zombie for an instant (reparented to
  # init) and a `kill -0` on a zombie exits the same — a zombie also
  # counts as dead here, what is asserted is that no one from the group
  # remains ALIVE.
  cat >waiter.py <<'PY'
import os
import signal
import subprocess
import sys
import time

gubia, marker = sys.argv[1], sys.argv[2]
lock = os.path.join(".gubia", "plan-plan.md.lock")
p = subprocess.Popen([gubia, "run", "plan/plan.md"],
                     stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL)


def read_marker():
    agent_pid = None
    terms = 0
    try:
        with open(marker) as f:
            for line in f:
                if line.startswith("agent-pid="):
                    agent_pid = int(line.split("=", 1)[1])
                elif line.startswith("terms="):
                    terms = int(line.split("=", 1)[1])
    except (FileNotFoundError, ValueError):
        pass
    return agent_pid, terms


agent_pid = None
deadline = time.time() + 10
while time.time() < deadline and agent_pid is None:
    agent_pid, _ = read_marker()
    if p.poll() is not None:
        break
    time.sleep(0.02)
if agent_pid is None:
    print("marker_seen=0")
    sys.exit(1)
print("marker_seen=1")
time.sleep(0.3)
os.kill(p.pid, signal.SIGINT)
signal.alarm(30)
_, status = os.waitpid(p.pid, 0)
sigint_death = os.WIFSIGNALED(status) and os.WTERMSIG(status) == signal.SIGINT
print("sigint_death=%d" % (1 if sigint_death else 0))
print("exit_code=%d" % (os.WEXITSTATUS(status) if os.WIFEXITED(status) else -1))


def alive(pid):
    try:
        with open("/proc/%d/stat" % pid) as f:
            state = f.read().rsplit(")", 1)[1].split()[0]
    except FileNotFoundError:
        return False
    return state != "Z"


deadline = time.time() + 10
while time.time() < deadline and alive(agent_pid):
    time.sleep(0.05)
print("agent_dead=%d" % (0 if alive(agent_pid) else 1))
_, terms = read_marker()
print("terms=%d" % terms)
print("lock_present=%d" % (1 if os.path.exists(lock) else 0))
PY
}

@test "SIGINT to the engine during an invocation: the trap closes the agent's group and re-raises the signal" {
  run python3 waiter.py "$GUBIA_BIN" "$repo/agent.marker"
  [ "$status" -eq 0 ]
  # The agent was running when the signal arrived: SIGINT during the
  # invocation, not before launching it nor after finishing.
  grep -q '^marker_seen=1$' <<<"$output"
  # Re-raise (`trap - INT; kill -INT "$$"`): the engine died BY SIGINT
  # (WIFSIGNALED, term 2). The `-1` declares "there was no exit code":
  # it is the direct refutation of `exit 130`, which here would give
  # WIFEXITED and code 130.
  grep -q '^sigint_death=1$' <<<"$output"
  grep -q '^exit_code=-1$' <<<"$output"
  # The trap closed the agent's group: exactly one TERM, signed only by
  # the engine (the `setsid` put the agent in another session; the
  # terminal's SIGINT never reaches it).
  grep -q '^terms=1$' <<<"$output"
  # No orphans: no one from the agent's group remains alive (the brief
  # zombie the engine leaves without reaping counts as dead).
  grep -q '^agent_dead=1$' <<<"$output"
  # The trap does not touch the lockfile: it stays forever.
  grep -q '^lock_present=1$' <<<"$output"
}

@test "reentrancy guard: with invoke_int_trap_active set, invoke_trap_int is a no-op" {
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  AGENT_MARKER="$repo/guard.marker"
  export AGENT_MARKER
  # Real victim in its own session group (the same fake CLI from the
  # PATH). It announces its own pid: from a script without job control,
  # the `$!` of a `setsid … &` is not reliable (util-linux forks or
  # execs depending on whether the subshell is a group leader).
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
  invoke_int_trap_active=yes
  invoke_interrupted=
  invoke_agent_pgid="$victim"

  invoke_trap_int

  # Total no-op: the interruption flag intact (task 06 would not
  # interpret a repeated signal as a new interruption), the victim
  # alive (the marker records no TERM) and no re-raise — a
  # `kill -INT "$$"` here would have killed this very test.
  [ -z "$invoke_interrupted" ]
  kill -0 "$victim" 2>/dev/null
  ! grep -q '^terms=' "$AGENT_MARKER"

  # Victim cleanup. The `wait` covers the case where it is still a child
  # of this shell (setsid execing without forking): without reaping it
  # it would stay a zombie stuck to the suite.
  kill -TERM -- -"$victim" 2>/dev/null || true
  wait "$victim" 2>/dev/null || true
}
