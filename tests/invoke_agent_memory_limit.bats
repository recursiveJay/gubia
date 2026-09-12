#!/usr/bin/env bats

# Test of the memory limit via systemd-run (plan/05.md, subtask
# "[create evidence] Add a bats-core test with a fake `systemd-run` in
# the `PATH` that verifies `invoke_agent` invokes it with
# `--user --scope -p MemoryMax=<memory_max>` when the tool is
# available").
#
# The fake `systemd-run` records its argv ONE LINE PER ARGUMENT and then
# `exec`s the command that follows the `--`: so the test verifies at
# once WHAT the wrapper received (the spec's literal formula) and that
# the agent really ran underneath — same PID, same group, with its fd 0
# intact. Because the fake `exec`s (does not fork), the chain
# `setsid systemd-run … -- agent` the test observes is isomorphic to the
# real one documented in `invoke_prepare`: `--scope` runs the command in
# its own process, so the child's PID == PGID == SID still holds with
# the wrapper in place.
#
# `memory_max` is set to a distinctive value (4G, not the default 8G) to
# demonstrate that `MemoryMax=` is taken from the configuration, not
# from a constant.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"
AGENTS_SH="${BATS_TEST_DIRNAME}/../config/agents.sh"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  bin="$repo/bin"
  mkdir -p "$bin" plan
  # Fake systemd-run: records its raw argv (one argument per line) and
  # execs the rest after the `--`. Without the exec, `wait` would return
  # the wrapper's rc and the agent would be orphaned from the contract.
  cat >"$bin/systemd-run" <<'CLI'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$SYSTEMD_RUN_ARGV_FILE"
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
  # Same fake CLI as invoke_agent_launch.bats: reports its fd 0, its
  # process group and where its streams went.
  cat >"$bin/fake-cli" <<'CLI'
#!/usr/bin/env bash
if timeout 1 cat >/dev/null 2>&1; then
  stdin_recibido="cat-eof"
else
  stdin_recibido="blocked"
fi
printf 'pid=%d pgid=%d sid=%d stdin=%s argv=%s\n' \
  "$$" "$(ps -o pgid= -p $$ | tr -d ' ')" "$(ps -o sid= -p $$ | tr -d ' ')" \
  "$stdin_recibido" "$*"
printf 'agent-stderr\n' >&2
exit 0
CLI
  chmod +x "$bin/systemd-run" "$bin/fake-cli"
  PATH="$bin:$PATH"
  SYSTEMD_RUN_ARGV_FILE="$repo/systemd-run.argv"
  export SYSTEMD_RUN_ARGV_FILE
  cat >plan/plan.md <<'PLAN'
# Plan
- [ ] [00. task](plan/00.md)
PLAN
}

# Minimal catalog with file transport — same contract as
# omp/devin in config/agents.sh.
fake_catalog() {
  agent_omp() {
    GUBIA_PROMPT_MODE='file'
    GUBIA_OUTPUT_MODE='stdout'
    GUBIA_ARGV=("$bin/fake-cli" "$4")
    GUBIA_ENV=()
  }
}

@test "with systemd-run available: invoke_agent invokes it with --user --scope -p MemoryMax=<memory_max>" {
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  # shellcheck source=/dev/null
  source "$AGENTS_SH"
  fake_catalog
  run_resolve_plan plan/plan.md
  run_acquire_lock
  run_export_env
  mkdir -p .gubia/logs
  memory_max=4G

  # The tool is in the PATH: silent detection (no fallback warning) and
  # the variable ready for invoke_prepare.
  require_tools >"$repo/require.out" 2>"$repo/require.err"
  [ ! -s "$repo/require.out" ]
  [ ! -s "$repo/require.err" ]
  [ "$invoke_systemd_run" = yes ]

  rc=0
  invoke_agent agent_omp m1 medium true 11 || rc=$?
  [ "$rc" -eq 0 ]

  # The wrapper received the spec's literal formula, with the configured
  # memory_max, in order, closed with `--` and followed by the agent's
  # argv (CLI + composed prompt path).
  [ -f "$repo/systemd-run.argv" ]
  cat >"$repo/expected.argv" <<EOF
--user
--scope
-q
-p
MemoryMax=4G
--
$bin/fake-cli
$run_root/.gubia/logs/11.prompt
EOF
  diff -u "$repo/expected.argv" "$repo/systemd-run.argv"

  # The agent ran UNDER the wrapper, not in its place: its streams fell
  # into the iteration's files, its fd 0 is still /dev/null (file mode)
  # and the PID it reports is still PID == PGID == SID — the `--scope`
  # own-process guarantee that this task's group teardown needs.
  grep -q 'stdin=cat-eof' .gubia/logs/11.out
  grep -q '^agent-stderr$' .gubia/logs/11.err
  ! grep -q 'agent-stderr' .gubia/logs/11.out
  local pid pgid sid
  pid="$(sed -n 's/^pid=\([0-9]*\) .*/\1/p' .gubia/logs/11.out)"
  pgid="$(sed -n 's/.* pgid=\([0-9]*\) .*/\1/p' .gubia/logs/11.out)"
  sid="$(sed -n 's/.* sid=\([0-9]*\) .*/\1/p' .gubia/logs/11.out)"
  [ -n "$pid" ]
  [ "$pid" = "$pgid" ]
  [ "$pid" = "$sid" ]
  ! kill -0 "$pid" 2>/dev/null
}
