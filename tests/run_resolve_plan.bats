#!/usr/bin/env bats

# Test of resolving the plan to an absolute path once at startup, with
# `die` if the path does not fall under the project root (plan/04.md:
# "Implement resolving the plan path to absolute once at startup, with
# `die` if the path does not fall under the project root").
#
# The `run_` module is sourced from the script (`BASH_SOURCE` guard):
# `run_resolve_plan` is called directly with the cwd fixed by the test,
# without going through `main` — the `run` dispatch arrives with its own
# subtask.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
}

@test "relative plan inside the root resolves to absolute under the root" {
  mkdir -p plan
  touch plan/plan.md
  run_resolve_plan plan/plan.md
  [ "$run_plan_abs" = "$PWD/plan/plan.md" ]
  [ "$run_root" = "$PWD" ]
}

@test "plan with .. that escapes the root dies with exit 2 even if the lexical prefix matches" {
  outside="$(mktemp -d)"
  touch "$outside/plan.md"
  run run_resolve_plan "$outside/plan.md"
  [ "$status" -eq 2 ]
  # The message names the resolved path and the root, not a plan read
  # error.
  grep -q 'does not fall under the project root' <<<"$output"
  grep -q "$outside/plan.md" <<<"$output"
}

@test "plan with .. that falls inside the root passes the guard" {
  mkdir -p plan
  touch plan/plan.md
  run_resolve_plan plan/../plan/plan.md
  [ "$run_plan_abs" = "$PWD/plan/plan.md" ]
}

@test "plan with a nonexistent directory dies with exit 2 and its own message" {
  run run_resolve_plan does-not-exist/plan.md
  [ "$status" -eq 2 ]
  grep -q 'cannot resolve plan path' <<<"$output"
}

@test "absolute plan path inside the root also passes the guard" {
  mkdir -p plan
  touch plan/plan.md
  run_resolve_plan "$PWD/plan/plan.md"
  [ "$run_plan_abs" = "$PWD/plan/plan.md" ]
  [ "$run_root" = "$PWD" ]
}