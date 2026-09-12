#!/usr/bin/env bats

# E2E test of the preflight over the versioned FIXTURE (plan/plan/10.md:
# "Add an e2e test (bats-core) that runs `gubia config validate`
# over the fixture and verifies exit 0"). It is the first green that the
# happy path of task 10 requires before launching `/gubia run`.
#
# Difference from `gubia_config_validate.bats`: that one composes the
# temporary repo by hand (`mktemp -d` + catalog written by the test,
# sibling of the task 04-06 suites); this one exercises the real fixture
# committed in `tests/fixtures/repo-minimo` — its `config/agents.sh` with
# the arrays and the fixture's `agent_probe`, not a catalog invented
# here. The copy to a temporary directory (`cp -a`, not the other tests)
# isolates the fixture: `state_ensure` writes its `.gubia/state.env` in
# the copy, and any future effect of the loop falls outside the
# controlled tree.
#
# It exercises the BINARY dispatched from `main` (`cmd_config_validate`
# sources the catalog in its scope and walks the fallback list of the
# active level), with a temporary `HOME` where the gubia/judge skills are
# installed — without touching the machine's real skills.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"
FIXTURE_DIR="${BATS_TEST_DIRNAME}/fixtures/repo-minimo"

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

# Installs the two required skills in the layout of a given harness —
# the same ones `config_harness_skills_dir` resolves in v1
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

# Installs in all four harnesses: the active level of the default state
# (medium) only mentions claude/omp/devin, but the fixture is the
# preflight of EVERY level that later tests launch — covering all four
# keeps this test green even if the level changes.
install_all() {
  local a
  for a in claude codex omp devin; do
    install_skills "$a"
  done
}

@test "config validate over the repo-minimo fixture exits 0 (preflight green)" {
  install_all
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 0 ]
  # Green = silence: any preflight diagnostic line is a warning that a
  # green validation should not emit.
  [ -z "$output" ]
}