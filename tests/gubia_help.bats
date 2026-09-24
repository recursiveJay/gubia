#!/usr/bin/env bats

# Test of the help (`-h`/`--help`/`help`) and of the nonexistent-plan
# guard in the `main` dispatch.
#
# `gubia run --help` must not interpret `--help` as `<path-to-plan>` and
# launch a loop: the help exits 0 without touching state or creating
# `.gubia/`. The nonexistent-plan guard aborts with exit 2 before the
# lock, without invoking the agent.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
}

teardown() {
  cd /
  rm -rf "$repo"
}

@test "gubia --help prints usage to stdout and exits 0 without creating state" {
  run "$GUBIA_BIN" --help
  [ "$status" -eq 0 ]
  grep -q 'usage: gubia run' <<<"$output"
  [ ! -e .gubia ]
}

@test "gubia -h and gubia help are aliases of the help" {
  for flag in -h help; do
    run "$GUBIA_BIN" "$flag"
    [ "$status" -eq 0 ]
    grep -q 'usage: gubia run' <<<"$output"
  done
  [ ! -e .gubia ]
}

@test "gubia run --help prints usage and does not launch the loop" {
  run "$GUBIA_BIN" run --help
  [ "$status" -eq 0 ]
  grep -q 'usage: gubia run' <<<"$output"
  [ ! -e .gubia ]
}

@test "gubia run -h prints usage and does not launch the loop" {
  run "$GUBIA_BIN" run -h
  [ "$status" -eq 0 ]
  grep -q 'usage: gubia run' <<<"$output"
  [ ! -e .gubia ]
}

@test "gubia run with a nonexistent plan aborts with exit 2 without taking the lock" {
  run "$GUBIA_BIN" run does-not-exist.md
  [ "$status" -eq 2 ]
  grep -q 'plan does not exist' <<<"$output"
  [ ! -e .gubia/does-not-exist.md.lock ]
}
