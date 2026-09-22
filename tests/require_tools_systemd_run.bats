#!/usr/bin/env bats

# Test of `systemd-run` detection in `require_tools` (plan/05.md,
# subtask "Add a bats-core test that simulates the absence and the
# presence of `systemd-run` in the `PATH` and verifies that
# `require_tools` emits a single warning on stderr when it is missing,
# allowing execution without a memory limit").
#
# The observable contract (vault/spec/engine.md, "Memory limit" +
# gotcha "detect once in a `require_tools` before the loop"):
#
# - `systemd-run` ABSENT from the `PATH` is not abortive: `require_tools`
#   returns 0, the iteration continues, and the warning goes to **stderr**
#   **only once** — the state variable avoids repeating it even though the
#   loop calls it on every iteration.
# - `systemd-run` PRESENT: no absence warning, and the variable that the
#   memory-limit subtask consumes stays at `yes` (the invocation WILL be
#   wrapped with systemd-run).
#
# Absence is simulated with a `PATH` reduced to a test directory that only
# carries the tools this test itself uses (grep): this way
# `command -v systemd-run` genuinely fails, not with a stub that could
# falsify the detection. Each @test of a bats file runs in the same
# process, so the teardown restores the `PATH` for the next test's setup.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  bin="$repo/bin"
  mkdir -p "$bin"
  _saved_path="$PATH"
  # External tools the test itself uses with the reduced PATH:
  # symlinks to the real ones, captured BEFORE touching the PATH.
  for t in grep; do
    ln -s "$(command -v "$t")" "$bin/$t"
  done
}

teardown() {
  # The absence test leaves the PATH reduced to $bin; without this, the
  # next test's setup (mktemp, ln) blows up.
  PATH="$_saved_path"
}

@test "without systemd-run in the PATH: a single stderr warning and execution continues without a memory limit" {
  PATH="$bin"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  # Detection is of a command in the PATH, not of cgroups: it is enough
  # that command -v does not find it.
  memory_max=8G

  # The first call warns on stderr AND ONLY on stderr (stdout clean:
  # warnings go to stderr, "Bash gotchas"), and returns 0: absence is
  # not abortive, the iteration runs without a limit.
  require_tools >"$repo/out.txt" 2>"$repo/err.txt"
  [ ! -s "$repo/out.txt" ]
  [ "$(grep -c 'without a memory limit' "$repo/err.txt")" -eq 1 ]
  grep -qF 'systemd-run not available in PATH' "$repo/err.txt"
  # The warning names the ignored memory_max: whoever reads it knows
  # which configuration stopped applying.
  grep -qF '(memory_max=8G ignored)' "$repo/err.txt"

  # Without systemd-run, the variable that the memory-limit subtask
  # consumes stays empty: the invocation will NOT be wrapped (runs
  # without a limit), and `ulimit -v` is never resorted to.
  [ -z "$invoke_systemd_run" ]
  [ "$invoke_tools_checked" = yes ]

  # SINGLE warning: the repeated call (the one the task 06 loop would
  # make on the next iteration) is free and adds no second warning —
  # exactly what the spec forbids.
  require_tools >>"$repo/err.txt" 2>&1
  [ "$(grep -c 'without a memory limit' "$repo/err.txt")" -eq 1 ]
}

@test "with systemd-run in the PATH: no warning and the limit variable is ready" {
  # Fake systemd-run: for require_tools it only matters that it exists
  # and is executable in the PATH; the real limit is the next subtask.
  cat >"$bin/systemd-run" <<'CLI'
#!/usr/bin/env bash
exit 0
CLI
  chmod +x "$bin/systemd-run"
  PATH="$bin:$PATH"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  memory_max=8G

  require_tools >"$repo/out.txt" 2>"$repo/err.txt"
  # Present: no absence warning, on any stream.
  [ ! -s "$repo/err.txt" ]
  [ ! -s "$repo/out.txt" ]
  [ "$invoke_systemd_run" = yes ]
  [ "$invoke_tools_checked" = yes ]

  # Idempotent with the tool present too: the second call emits nothing
  # and does not re-detect.
  require_tools >>"$repo/out.txt" 2>>"$repo/err.txt"
  [ ! -s "$repo/err.txt" ]
  [ ! -s "$repo/out.txt" ]
}
