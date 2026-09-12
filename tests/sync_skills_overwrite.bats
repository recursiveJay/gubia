#!/usr/bin/env bats

# Test of the `sync-skills` target of the justfile (plan/09.md): checks
# that it overwrites an already-installed skill file with the CURRENT
# content of the repo, even if the installed file is committed in its own
# git repo (this rules out `sync-skills` doing anything finer than a plain
# copy, such as preserving what was installed because it is under version
# control).
#
# `HOME` points to a temporary directory and `PATH` is prepended with a
# fake `claude`, so the target detects that single harness and does not
# touch anything on the real system. The real repo (with its current
# `justfile` and `skills/`) is run with `--working-directory` so that the
# relative paths `skills/gubia/` and `skills/judge/` resolve against the
# repo, not the temporary `$HOME`.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
  home="$(mktemp -d)"
  fakebin="$(mktemp -d)"
  cat >"$fakebin/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fakebin/claude"

  # Already-installed skill file, with content different from the current
  # repo one, committed in its own git repo (simulates that what was
  # installed is under version control, e.g. a dotfiles repo).
  installed_dir="$home/.claude/skills/gubia"
  mkdir -p "$installed_dir"
  printf 'contenido viejo, previo a este sync\n' >"$installed_dir/SKILL.md"
  git -C "$installed_dir" init -q
  git -C "$installed_dir" -c user.email=t@t -c user.name=t add SKILL.md
  git -C "$installed_dir" -c user.email=t@t -c user.name=t commit -q -m "previous installation"
}

teardown() {
  rm -rf "$home" "$fakebin"
}

@test "sync-skills overwrites an already-installed (and committed) skill with the current repo content" {
  PATH="$fakebin:$PATH" HOME="$home" \
    run just --justfile "$REPO_ROOT/justfile" --working-directory "$REPO_ROOT" sync-skills
  [ "$status" -eq 0 ]

  diff "$REPO_ROOT/skills/gubia/SKILL.md" "$home/.claude/skills/gubia/SKILL.md"
  diff "$REPO_ROOT/skills/judge/SKILL.md" "$home/.claude/skills/judge/SKILL.md"

  # The previous file was still committed in its own git repo: the sync
  # overwrote it anyway, without checking whether it was under version
  # control.
  ! grep -q 'contenido viejo, previo a este sync' "$home/.claude/skills/gubia/SKILL.md"
}
