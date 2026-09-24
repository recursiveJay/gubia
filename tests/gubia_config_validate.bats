#!/usr/bin/env bats

# Test of the installed-skills check in `gubia config validate`
# (plan/06.md: "Implement in `gubia config validate` the check that the
# `gubia`/`judge` skills are installed in the harness of each model in
# the active fallback list").
#
# The BINARY dispatched from `main` is exercised (not the sourced
# functions): what is proper to `config validate` is the real path the
# preflight takes, with `state.env` read and the catalog sourced in the
# scope of `cmd_config_validate`. A temporary `HOME` isolates the test
# from the developer's real layout and lets the test install/uninstall
# skills without touching the machine.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  home="$repo/home"
  mkdir -p "$home" config
  # Minimal catalog that defines the four agent functions (so that
  # `config_validate_agent_functions` passes) and a `medium` fallback
  # list with one model per agent. The argv/env don't matter here:
  # `config validate` invokes no agent, it only walks the catalog.
  cat >config/agents.sh <<'AGENTS'
agent_codex()  { GUBIA_ARGV=(codex); GUBIA_ENV=(); }
agent_claude() { GUBIA_ARGV=(claude); GUBIA_ENV=(); }
agent_omp()    { GUBIA_ARGV=(omp); GUBIA_ENV=(); }
agent_devin()  { GUBIA_ARGV=(devin); GUBIA_ENV=(); }

declare -rA GUBIA_MODELS=(
  [codex-medium]="codex gpt-5.6-terra"
  [claude-medium]="claude sonnet"
  [omp-medium]="omp deepseek-v4-pro:0813"
  [devin-medium]="devin swe-1.7-lightning"
  [devin-high]="devin opus"
  [bogus-medium]="foo bar"
)
declare -ra GUBIA_FALLBACK_MEDIUM=(
  codex-medium
  claude-medium
  omp-medium
  devin-medium
)
AGENTS
}

teardown() {
  cd /
  rm -rf "$repo"
}

# Installs the two required skills in a given agent's layout.
# The layouts are the ones `config_harness_skills_dir` resolves in v1
# (claude/codex/omp/devin); the temporary `HOME` isolates them from the
# real one.
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

# Installs the skills in the four harnesses of the test's catalog.
install_all() {
  local a
  for a in codex claude omp devin; do
    install_skills "$a"
  done
}

@test "config validate exits 0 when gubia and judge are installed in each harness of the active list" {
  install_all
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 0 ]
}

@test "the fallback uses local config/agents.sh when it exists (without GUBIA_AGENTS_SH)" {
  install_all
  HOME="$home" run "$GUBIA_BIN" config validate
  [ "$status" -eq 0 ]
}

@test "the fallback uses ~/.config/gubia/agents.sh when there is no local config/agents.sh" {
  mkdir -p "$home/.config/gubia"
  cp config/agents.sh "$home/.config/gubia/agents.sh"
  rm config/agents.sh
  install_all
  HOME="$home" run "$GUBIA_BIN" config validate
  [ "$status" -eq 0 ]
}

# --- Case 1: agents.sh missing one of the four agent functions ---

# Sourceable catalog that defines only three of the four functions: the
# fourth (`agent_devin`) is missing on purpose. The fallback list does
# not reference devin, so `config_validate_skills` does not complain
# about devin's harness and the verdict comes only from the incomplete
# catalog.
write_agents_missing_devin() {
  cat >config/agents.sh <<'AGENTS'
agent_codex()  { GUBIA_ARGV=(codex); GUBIA_ENV=(); }
agent_claude() { GUBIA_ARGV=(claude); GUBIA_ENV=(); }
agent_omp()    { GUBIA_ARGV=(omp); GUBIA_ENV=(); }

declare -rA GUBIA_MODELS=(
  [codex-medium]="codex gpt-5.6-terra"
  [claude-medium]="claude sonnet"
  [omp-medium]="omp deepseek-v4-pro:0813"
)
declare -ra GUBIA_FALLBACK_MEDIUM=(
  codex-medium
  claude-medium
  omp-medium
)
AGENTS
}

@test "config validate fails (exit 2) and names the agent function missing from the catalog" {
  write_agents_missing_devin
  # Skills installed in the three harnesses that are in the list:
  # isolates the failure to the incomplete catalog, not to the skills.
  install_skills codex
  install_skills claude
  install_skills omp
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 2 ]
  grep -q 'does not define agent_devin (incomplete catalog)' <<<"$output"
}

@test "config validate fails (exit 2) when each of the four functions is missing, one at a time" {
  local fn
  for fn in agent_codex agent_claude agent_omp agent_devin; do
    # Rebuilds the catalog skipping the iteration's function.
    : >config/agents.sh
    local f
    for f in agent_codex agent_claude agent_omp agent_devin; do
      [[ "$f" == "$fn" ]] && continue
      printf '%s() { GUBIA_ARGV=(x); GUBIA_ENV=(); }\n' "$f" >>config/agents.sh
    done
    # Empty fallback list: with no models to walk, the skills add no
    # noise and the verdict is only from the catalog.
    printf 'declare -ra GUBIA_FALLBACK_MEDIUM=()\n' >>config/agents.sh
    GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
      run "$GUBIA_BIN" config validate
    [ "$status" -eq 2 ]
    grep -q "does not define $fn (incomplete catalog)" <<<"$output"
  done
}

# --- Case 2: one of the 6 valid scalars missing or out of domain ---

# Writes a complete, valid `state.env` (the six scalars within domain).
# `state_ensure` does not touch it if it already exists, so the file
# written here is the one the engine sees at startup.
write_valid_state() {
  mkdir -p .gubia
  cat >.gubia/state.env <<'EOF'
effort_level=medium
fallback_list=default
model_index=0
thinking=true
memory_max=8G
loop_max_logs=20
EOF
}

@test "config validate fails (exit 2) when one of the six state.env keys is missing" {
  write_valid_state
  install_all
  # Deletes a key that ONLY `config_validate_scalars` validates (not
  # `state_validate`, which is abortive over effort_level/thinking/
  # model_index): so the flow reaches `cmd_config_validate` and it is
  # the presence check that reports the missing key.
  sed -i '/^loop_max_logs=/d' .gubia/state.env
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 2 ]
  grep -q 'missing keys: loop_max_logs (corrupt file)' <<<"$output"
}

@test "config validate fails (exit 2) when a state.env scalar is out of domain" {
  write_valid_state
  install_all
  # `fallback_list` is only validated by `config_validate_scalars`
  # (domain `default`): a different value reaches the preflight and is
  # reported as an invalid value, not as a missing key.
  sed -i 's|^fallback_list=.*|fallback_list=bogus|' .gubia/state.env
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 2 ]
  grep -q 'invalid value for fallback_list: bogus (expected: default)' <<<"$output"
}

@test "config validate fails (exit 2) when effort_level is out of domain (abortive state_validate validation)" {
  write_valid_state
  install_all
  # `effort_level` is validated by `state_validate` abortively (exit 2)
  # before dispatching to `cmd_config_validate`: the observable result
  # is the same — `gubia config validate` ends with exit ≠ 0.
  sed -i 's|^effort_level=.*|effort_level=bogus|' .gubia/state.env
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 2 ]
  grep -q 'invalid value for effort_level: bogus (expected: low|medium|high)' <<<"$output"
}

@test "config validate fails (exit 2) and names the skill and the agent when a skill is missing in a harness" {
  install_all
  rm "$home/.codex/skills/judge/SKILL.md"
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 2 ]
  grep -q 'skill judge not installed in the harness for codex' <<<"$output"
  grep -q '\.codex/skills/judge/SKILL.md' <<<"$output"
}

@test "dedup: two models of the same agent are checked only once" {
  # `medium` list with two devin entries: devin's harness is checked
  # only once even though it appears twice.
  cat >>config/agents.sh <<'AGENTS'
declare -ra GUBIA_FALLBACK_HIGH=(
  devin-medium
  devin-high
)
AGENTS
  install_all
  rm "$home/.config/devin/skills/gubia/SKILL.md"
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" effort set high
  [ "$status" -eq 0 ]
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 2 ]
  # Exactly one complaint line about devin: the dedup prevents the
  # second devin model from repeating the same check.
  [ "$(grep -c 'harness for devin' <<<"$output")" -eq 1 ]
}

@test "a model in the list not defined in GUBIA_MODELS is reported and fails" {
  cat >>config/agents.sh <<'AGENTS'
declare -ra GUBIA_FALLBACK_LOW=(
  codex-medium
  missing-low
)
AGENTS
  install_all
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" effort set low
  [ "$status" -eq 0 ]
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 2 ]
  grep -q 'model missing-low in the fallback list not defined in GUBIA_MODELS' <<<"$output"
}

@test "an agent with no known skills layout is reported and fails" {
  cat >>config/agents.sh <<'AGENTS'
declare -ra GUBIA_FALLBACK_HIGH=(
  bogus-medium
)
AGENTS
  install_all
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" effort set high
  [ "$status" -eq 0 ]
  GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 2 ]
  grep -q 'agent foo has no known skills layout' <<<"$output"
}

@test "without a sourceable catalog the fallback list is not walked" {
  # Catalog with broken syntax: the `source` blows up, the skills check
  # is skipped (without arrays there is no list) and the verdict comes
  # from the catalog, not from the skills.
  printf 'fi\n' >config/broken.sh
  GUBIA_AGENTS_SH="$repo/config/broken.sh" HOME="$home" \
    run "$GUBIA_BIN" config validate
  [ "$status" -eq 2 ]
  ! grep -q 'skill' <<<"$output"
  grep -q 'cannot be sourced' <<<"$output"
}
