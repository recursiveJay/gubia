#!/usr/bin/env bats

# Test of the justfile `sync-skills` target (plan/09.md): checks that it
# detects which harnesses (`claude`, `codex`, `omp`, `devin`) are present
# on the machine and syncs ONLY those: each present harness receives the
# skills in its own layout, and for the absent ones not even the
# destination directory is created.
#
# `HOME` points to a temporary directory and `PATH` is prepended with fake
# binaries for the harnesses the case wants present; the ones without a
# stub are not detected. This way the target never touches anything on the
# real system. The real repo (with its current `justfile` and `skills/`)
# runs with `--working-directory` so that the relative paths
# `skills/gubia/` and `skills/judge/` resolve against the repo, not the
# temporary `$HOME`.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

# Harness stub: the binary only needs to exist and be executable, which is
# all `command -v` checks to decide presence.
add_harness() {
  cat >"$fakebin/$1" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fakebin/$1"
}

setup() {
  home="$(mktemp -d)"
  fakebin="$(mktemp -d)"
}

teardown() {
  rm -rf "$home" "$fakebin"
}

@test "claude as the only present harness: installs in its layout and skips the rest" {
  add_harness claude

  PATH="$fakebin:/usr/bin:/bin" HOME="$home" \
    run just --justfile "$REPO_ROOT/justfile" --working-directory "$REPO_ROOT" sync-skills
  [ "$status" -eq 0 ]

  # Claude's layout populated with the repo's current content.
  diff "$REPO_ROOT/skills/gubia/SKILL.md" "$home/.claude/skills/gubia/SKILL.md"
  diff "$REPO_ROOT/skills/judge/SKILL.md" "$home/.claude/skills/judge/SKILL.md"

  # For codex, devin and omp (absent) not even the destination directory
  # is created.
  [ ! -e "$home/.codex" ]
  [ ! -e "$home/.config/devin" ]
  [ ! -e "$home/.omp" ]

  # The result explicitly announces the skipped ones.
  [[ "$output" == *"skipped: codex"* ]]
  [[ "$output" == *"skipped: devin"* ]]
  [[ "$output" == *"skipped: omp"* ]]
}

@test "codex and omp present: installed in their layouts, claude and devin skipped" {
  add_harness codex
  add_harness omp

  PATH="$fakebin:/usr/bin:/bin" HOME="$home" \
    run just --justfile "$REPO_ROOT/justfile" --working-directory "$REPO_ROOT" sync-skills
  [ "$status" -eq 0 ]

  # Layouts of the present ones, each with the repo's current content.
  diff "$REPO_ROOT/skills/gubia/SKILL.md" "$home/.codex/skills/gubia/SKILL.md"
  diff "$REPO_ROOT/skills/judge/SKILL.md" "$home/.codex/skills/judge/SKILL.md"
  diff "$REPO_ROOT/skills/gubia/SKILL.md" "$home/.omp/agent/skills/gubia/SKILL.md"
  diff "$REPO_ROOT/skills/judge/SKILL.md" "$home/.omp/agent/skills/judge/SKILL.md"

  [ ! -e "$home/.claude" ]
  [ ! -e "$home/.config/devin" ]
}

@test "all four present: each receives the skills in its own layout" {
  add_harness claude
  add_harness codex
  add_harness devin
  add_harness omp

  PATH="$fakebin:/usr/bin:/bin" HOME="$home" \
    run just --justfile "$REPO_ROOT/justfile" --working-directory "$REPO_ROOT" sync-skills
  [ "$status" -eq 0 ]

  for dst in \
    "$home/.claude/skills" \
    "$home/.codex/skills" \
    "$home/.config/devin/skills" \
    "$home/.omp/agent/skills"; do
    for name in gubia judge; do
      diff "$REPO_ROOT/skills/$name/SKILL.md" "$dst/$name/SKILL.md"
    done
  done
}
