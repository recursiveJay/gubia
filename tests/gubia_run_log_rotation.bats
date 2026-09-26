#!/usr/bin/env bats

# E2e test of the post-iteration log rotation over the `repo-minimal`
# fixture (plan/task/02.md): after a drained run with
# `loop_max_logs=K` (K < N), `.gubia/logs/` holds files for at most K
# iterations, and the retained sets are the K most recent (R2/R3).
#
# Same isolation as `gubia_run_fixture_drain.bats`: the fixture is copied
# to a temporary directory, the catalog points at its fake CLI (scripted
# exit codes, no network), and `.gubia/state.env` is pre-written with a
# small `loop_max_logs` so the pruner has something to delete.

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

install_all() {
  local a
  for a in claude codex omp devin; do
    install_skills "$a"
  done
}

# Pre-writes `.gubia/state.env` with the full six-key defaults and the
# given `loop_max_logs`, so the run starts already configured (the engine
# only creates the file when it does not exist).
write_state() {
  local limit="$1"
  mkdir -p .gubia
  cat >.gubia/state.env <<EOF
effort_level=medium
fallback_list=default
model_index=0
thinking=true
memory_max=8G
loop_max_logs=${limit}
EOF
}

# Distinct numeric prefixes of the retained `.prompt` anchors, sorted
# ascending — one per surviving iteration set.
retained_prefixes() {
  local f name
  for f in .gubia/logs/*.prompt; do
    [[ -f "$f" ]] || continue
    name="${f##*/}"
    printf '%s\n' "${name%.prompt}"
  done | sort -n
}

@test "a drained run with loop_max_logs=2 keeps at most 2 recent iteration sets" {
  install_all
  write_state 2
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 0 ]

  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run timeout 60 "$GUBIA_BIN" run plan/plan.md 10
  [ "$status" -eq 0 ]
  grep -q 'stop file present' <<<"$output"

  # The run drains 4 turns (3 subtasks + 1 creating stop.md); with a
  # limit of 2 the pruner must leave exactly the two most recent sets
  # (prefixes 3 and 4), every suffix of each.
  [ "$(retained_prefixes | tr '\n' ' ')" = '3 4 ' ]
  for prefix in 3 4; do
    for suffix in prompt out err; do
      [ -f ".gubia/logs/${prefix}.${suffix}" ]
    done
  done
  # The pruned sets are gone atomically, every suffix.
  for prefix in 1 2; do
    for suffix in prompt out err console; do
      [ ! -e ".gubia/logs/${prefix}.${suffix}" ]
    done
  done
}

@test "loop_max_logs=1 keeps exactly the current set after a drained run" {
  install_all
  write_state 1
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 0 ]

  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run timeout 60 "$GUBIA_BIN" run plan/plan.md 10
  [ "$status" -eq 0 ]
  grep -q 'stop file present' <<<"$output"

  # Only the most recent iteration's set (prefix 4) survives.
  [ "$(retained_prefixes | tr '\n' ' ')" = '4 ' ]
  for suffix in prompt out err; do
    [ -f ".gubia/logs/4.${suffix}" ]
  done
  for prefix in 1 2 3; do
    for suffix in prompt out err console; do
      [ ! -e ".gubia/logs/${prefix}.${suffix}" ]
    done
  done
}

@test "two consecutive runs write strictly non-overlapping, monotonic prefixes" {
  install_all
  write_state 20
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 0 ]

  # First run drains the 3 subtasks and stops via the ceiling (no stop
  # file), writing sets 1, 2 and 3 (well under the 20-set limit, so
  # nothing is pruned).
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" run plan/plan.md 3
  [ "$status" -eq 0 ]
  grep -q 'max_iterations reached' <<<"$output"
  [ -f .gubia/logs/1.prompt ]
  [ -f .gubia/logs/2.prompt ]
  [ -f .gubia/logs/3.prompt ]

  # Second run: no pending subtasks remain, so its first iteration
  # creates stop.md. The monotonic log sequence number continues from
  # the highest existing prefix (3), so this round writes set 4 —
  # never colliding with the first run's `1`/`2`/`3`.
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" run plan/plan.md 3
  [ "$status" -eq 0 ]
  grep -q 'stop file present' <<<"$output"

  # The two runs' sets are strictly non-overlapping and monotonic: the
  # second run continued at 4 instead of restarting at 1, and no set
  # beyond it was created.
  [ "$(retained_prefixes | tr '\n' ' ')" = '1 2 3 4 ' ]
  [ -f .gubia/logs/4.prompt ]
  [ ! -e .gubia/logs/5.prompt ]
}
