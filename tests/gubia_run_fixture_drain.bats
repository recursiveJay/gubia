#!/usr/bin/env bats

# E2e test of the full happy path over the versioned FIXTURE
# (plan/plan/10.md: "Add an e2e test (bats-core) that runs
# `gubia run` over the fixture's plan and verifies it creates `stop.md`
# next to the plan after draining all subtasks").
#
# It is the culmination of task 10: where `gubia_config_validate_fixture.bats`
# only tests the preflight, this one chains the full happy path —
# `config validate` green and then `gubia run` draining the fixture's
# plan one subtask per iteration until `stop.md` is created next to the
# plan, with no human intervention. Each iteration's agent is the
# fixture catalog's `agent_probe`, which points at `fake-cli.sh`
# (scripted exit codes, no network or credentials), and the tests count
# real loop turns with the fake CLI's own `tick` witness — the same
# pattern as the e2e suites of tasks 04-06.
#
# Like that one, it copies the fixture to a temporary directory (`cp -a`)
# to isolate it: the `.gubia/` state, the effects (`greeting.txt`,
# `output/echo.txt`, `done.flag`) and `stop.md` itself are born in the
# copy, and the committed fixture stays intact.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"
FIXTURE_DIR="${BATS_TEST_DIRNAME}/fixtures/repo-minimal"

setup() {
  repo="$(mktemp -d)"
  cp -a "$FIXTURE_DIR/." "$repo/"
  cd "$repo"
  home="$repo/home"
  mkdir -p "$home"
}

teardown() {
  cd /
  rm -rf "$repo"
}

# Installs the two required skills in a given harness's layout — the
# same ones `config_harness_skills_dir` resolves in v1
# (claude/codex/omp/devin), inside the temporary `HOME`.
install_skills() {
  local agent="$1" dir
  case "$agent" in
    claude) dir="$home/.claude/skills" ;;
    codex)  dir="$home/.codex/skills" ;;
    omp)    dir="$home/.omp/agent/skills" ;;
    devin)  dir="$home/.config/devin/skills" ;;
    *) return 1 ;;
  esac
  mkdir -p "$dir/gubia" "$dir/judge"
  printf 'name: gubia\n' >"$dir/gubia/SKILL.md"
  printf 'name: judge\n' >"$dir/judge/SKILL.md"
}

# Installs in all four harnesses: the default active level (medium) only
# requires claude/omp/devin, but the fixture is the preflight of EVERY
# level that future tests launch over this copy.
install_all() {
  local a
  for a in claude codex omp devin; do
    install_skills "$a"
  done
}

# Real loop turns: each invocation of the fake CLI appends a `tick` to
# the witness (outside `.gubia/` so it does not mix with the engine's
# state).
ticks() {
  grep -c '^tick$' "$repo/.fixture-log/marker.log" 2>/dev/null || printf '0\n'
}

@test "gubia run over the fixture drains the subtasks and creates stop.md next to the plan" {
  # Preflight green before launching (task 10's happy path:
  # `config validate` first, `gubia run` after).
  install_all
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # Guard against a contaminated fixture: the stop file must be born
  # from THIS run, not travel committed with the copy.
  [ ! -e "$repo/plan/stop.md" ]

  # Cap 10, roomy over the 4 drain turns (3 subtasks + 1 that creates
  # the stop file) and bounding the worst case: if the loop hung,
  # `timeout` kills the test in 60s.
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run timeout 60 "$GUBIA_BIN" run plan/plan.md 10
  [ "$status" -eq 0 ]
  # Normal exit via stop file, NOT via cap (two distinct exit 0s).
  grep -q 'stop file present' <<<"$output"
  ! grep -q 'max_iterations reached' <<<"$output"

  # The stop file is born NEXT TO THE PLAN, with the contract's short note.
  [ -f "$repo/plan/stop.md" ]
  grep -q 'plan completo, sin subtareas pendientes' "$repo/plan/stop.md"

  # Full drain: neither the plan nor its task files keep pending items
  # (propagation pushed the `[x]` up to every entry).
  ! grep -rq -- '- \[ \]' "$repo/plan/"

  # Trivial effects of each subtask, with exact content.
  [ "$(cat "$repo/greeting.txt")" = 'hello fixture' ]
  [ "$(cat "$repo/output/echo.txt")" = 'fixture echo' ]
  [ "$(cat "$repo/done.flag")" = 'done' ]

  # One subtask per invocation: 3 draining + 1 repeated (the fake CLI's
  # success signal does not stop the iteration; the turn that WOULD
  # create the stop file creates it), and the fifth no longer invokes
  # the agent — the stop file is checked when opening each iteration.
  [ "$(ticks)" -eq 4 ]
  [ "$(grep -l -- '^SUBTAREA_COMPLETADA=true$' "$repo"/.gubia/logs/*.out | wc -l)" -eq 4 ]
  [ ! -e "$repo/.gubia/logs/5.out" ]
  [ ! -e "$repo/.gubia/logs/5.prompt" ]
}