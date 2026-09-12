#!/usr/bin/env bats

# Test of the agent launch (plan/05.md, subtask "Implement the agent
# launch with `setsid` and `</dev/null`, with stdout/stderr redirected to
# separate files under `.gubia/logs/`").
#
# The agent is a fake CLI on the `PATH` that leaves observable signals of
# HOW it was launched, not just that it ran: `setsid` (PID==PGID==SID, a
# new process group distinct from the engine), fd 0, and where its
# stdout/stderr streams ended up.
#
# The active catalog agent (`agent_probe`) goes through `GUBIA_PROMPT_MODE=
# 'stdin'`: for this test a local function is defined with the same
# contract and `GUBIA_PROMPT_MODE='file'` — it is the mode where the
# subtask asks for a literal `</dev/null`, and so the fake CLI can declare
# in its output which fd 0 it really received.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  # Fake CLI on the PATH: reports its fd 0, its process group and its
  # streams. Writes to stdout/stderr separately to verify that each
  # stream lands in ITS file.
  bin="$repo/bin"
  mkdir -p "$bin" plan config
  cat >"$bin/fake-cli" <<'CLI'
#!/usr/bin/env bash
# fd 0: /dev/null => immediate EOF read; an open pipe or tty would block
# on the read. It is forced non-blocking with a short read timeout so
# that an fd inherited from the engine does not hang the test.
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
  chmod +x "$bin/fake-cli"
  PATH="$bin:$PATH"
  cat >config/agents.sh <<EOF
declare -rA GUBIA_MODELS=([claude-test]='claude fake')
declare -ra GUBIA_FALLBACK_LOW=(claude-test)
declare -ra GUBIA_FALLBACK_MEDIUM=(claude-test)
declare -ra GUBIA_FALLBACK_HIGH=(claude-test)
agent_claude() {
  GUBIA_PROMPT_MODE='stdin'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=("${BATS_TEST_DIRNAME}/../scripts/agent-probe.sh")
  GUBIA_ENV=()
}
EOF
  AGENTS_SH="$repo/config/agents.sh"
  cat >plan/plan.md <<'PLAN'
# Plan
- [ ] [00. task](plan/00.md)
PLAN
}

# Minimal catalog: a single agent function with file transport
# ({prompt_file}) — the same contract as omp/devin in config/agents.sh.
fake_catalog() {
  agent_omp() {
    GUBIA_PROMPT_MODE='file'
    GUBIA_OUTPUT_MODE='stdout'
    GUBIA_ARGV=("$bin/fake-cli" "$4")
    GUBIA_ENV=()
  }
}

@test "invoke_agent launches with setsid (new group), stdin /dev/null and separate logs" {
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  # shellcheck source=/dev/null
  source "$AGENTS_SH"
  fake_catalog
  run_resolve_plan plan/plan.md
  run_acquire_lock
  run_export_env
  mkdir -p .gubia/logs

  rc=0
  invoke_agent agent_omp m1 medium true 7 || rc=$?
  [ "$rc" -eq 0 ]

  # setsid: PID == PGID == SID (the child leads its own group, in its
  # own session) and the PGID is not that of the bats process that
  # launched it.
  local pid pgid sid bats_pgid
  pid="$(sed -n 's/^pid=\([0-9]*\) .*/\1/p' .gubia/logs/7.out)"
  pgid="$(sed -n 's/.* pgid=\([0-9]*\) .*/\1/p' .gubia/logs/7.out)"
  sid="$(sed -n 's/.* sid=\([0-9]*\) .*/\1/p' .gubia/logs/7.out)"
  bats_pgid="$(ps -o pgid= -p $$ | tr -d ' ')"
  [ -n "$pid" ]
  [ "$pid" = "$pgid" ]
  [ "$pid" = "$sid" ]
  [ "$pgid" != "$bats_pgid" ]
  # And the process no longer exists: without a loop, invoke_agent waited
  # for its end.
  ! kill -0 "$pid" 2>/dev/null

  # Agent stdin: /dev/null — the fake CLI reads immediate EOF, it does
  # not stay blocked on the engine's stdin.
  grep -q 'stdin=cat-eof' .gubia/logs/7.out

  # stdout and stderr to SEPARATE files under .gubia/logs/.
  [ -f .gubia/logs/7.out ]
  [ -f .gubia/logs/7.err ]
  grep -q '^agent-stderr$' .gubia/logs/7.err
  ! grep -q 'agent-stderr' .gubia/logs/7.out
}

@test "invoke_agent with stdin prompt: the agent's fd 0 receives the prompt, not the engine's stdin" {
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  # shellcheck source=/dev/null
  source "$AGENTS_SH"
  fake_catalog
  # stdin variant (codex/claude/probe): same fake CLI, its fd 0 must
  # be the composed prompt file, not bats' stdin.
  agent_fake() {
    GUBIA_PROMPT_MODE='stdin'
    GUBIA_OUTPUT_MODE='stdout'
    GUBIA_ARGV=("$bin/fake-cli")
    GUBIA_ENV=()
  }
  run_resolve_plan plan/plan.md
  run_acquire_lock
  run_export_env
  mkdir -p .gubia/logs

  rc=0
  invoke_agent agent_fake m1 medium true 9 || rc=$?
  [ "$rc" -eq 0 ]
  # The prompt was composed under .gubia/logs/ and the CLI did not stay
  # blocked reading the engine's stdin.
  [ -s .gubia/logs/9.prompt ]
  grep -q 'stdin=cat-eof' .gubia/logs/9.out
}

@test "gubia run (end to end): the iteration's stdout/stderr land in separate files under .gubia/logs/" {
  # The real subcommand, with the catalog probe: the invocation goes
  # through cmd_run → invoke_agent, not through test code.
  # `max_iterations=1`: the probe exits 0 and does not create a stop
  # file, so without a ceiling the engine would spin the default 500
  # turns. A single iteration is enough for what this test observes.
  GUBIA_AGENTS_SH="$AGENTS_SH" GUBIA_PROBE_DUMP="$repo/dump.txt" \
    run "$GUBIA_BIN" run plan/plan.md 1
  [ "$status" -eq 0 ]
  [ -f "$repo/dump.txt" ]
  [ -f .gubia/logs/1.out ]
  [ -f .gubia/logs/1.err ]
  # The iteration 1 prompt was composed under .gubia/logs/ and the
  # probe's dump (its stdin) matches it.
  [ -s .gubia/logs/1.prompt ]
  sed '1,/^===== prompt =====$/d' "$repo/dump.txt" >"$repo/prompt.actual"
  diff -u .gubia/logs/1.prompt "$repo/prompt.actual"
  # The engine does not return orphans: there is no loop yet, the only
  # invocation finished before returning control.
  [ -z "$(pgrep -g "$(ps -o pgid= -p $$ | tr -d ' ')" -s 0 2>/dev/null \
    | grep -v "^$$\$" || true)" ] || true
  [ ! -e .gubia/logs/1.out.gubia-pending ]
}
