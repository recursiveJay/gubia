# justfile — repo quality harnesses.
#
# bats-core is vendored as a git submodule at tests/vendor/bats-core (no
# system package is available on this machine). After cloning the repo, or
# if tests/vendor/bats-core/bin/bats doesn't exist, install it with:
#
#   git submodule update --init tests/vendor/bats-core
#
# `just test` invokes it directly over tests/*.bats.

# Runs the test suite with bats-core.
test:
    tests/vendor/bats-core/bin/bats tests/*.bats

# Runs shellcheck over the repo's bash scripts (none vendored).
# `xargs -r` avoids failing when there's no *.sh script yet.
lint:
    find . -path ./.git -prune -o -path './tests/vendor' -prune -o -type f -name '*.sh' -print \
        | xargs -r shellcheck -x

# Syncs skills/gubia/, skills/judge/ and skills/scribe/ to the layout of each harness in the
# catalog (`claude`, `codex`, `omp`, `devin`) present on this machine,
# overwriting whatever is installed under that name. The repo's skills are
# the source; local versions aren't preserved. Only the human runs this:
# never the loop or an iteration.
#
# Presence detection and destination layout for each harness (per-skill
# directory with SKILL.md inside, overwritable by copy):
#   - claude: `claude` binary on PATH -> ~/.claude/skills/<name>/SKILL.md
#   - codex:  `codex` binary on PATH  -> ~/.codex/skills/<name>/SKILL.md
#   - devin:  `devin` binary on PATH  -> ~/.config/devin/skills/<name>/SKILL.md
#   - omp:    `omp` binary on PATH    -> ~/.omp/agent/skills/<name>/SKILL.md
#     (user-level skills, global; `.omp/skills/<name>/SKILL.md` is the
#     project-level equivalent)
sync-skills:
    #!/usr/bin/env bash
    set -euo pipefail
    declare -A dsts=(
        [claude]="$HOME/.claude/skills"
        [codex]="$HOME/.codex/skills"
        [devin]="$HOME/.config/devin/skills"
        [omp]="$HOME/.omp/agent/skills"
    )
    for harness in claude codex devin omp; do
        if ! command -v "$harness" >/dev/null 2>&1; then
            echo "skipped: $harness not present on this machine"
            continue
        fi
        dst="${dsts[$harness]}"
        for name in gubia judge scribe; do
            rm -rf "$dst/$name"
            mkdir -p "$dst/$name"
            cp -R "skills/$name/." "$dst/$name/"
            echo "installed ($harness): $dst/$name"
        done
    done

# Installs on the machine what `gubia config validate` requires before
# `gubia run` can start (see `vault/spec/installation.md`): the `gubia`
# binary on the user's PATH and the global `agents.sh` catalog at
# `~/.config/gubia/`. Human/engine config, never an iteration's: only the
# human runs this, same as sync-skills, and it overwrites whatever is
# installed under that name — the repo is the source.
#
# `gubia` is symlinked so a later `git pull` doesn't require reinstalling;
# `agents.sh` is copied because the file itself is the user's editable
# catalog config on that machine, not an artifact that should track the
# repo live.
install-config:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "$HOME/.local/bin" "$HOME/.config/gubia"
    ln -sf "$(pwd)/gubia" "$HOME/.local/bin/gubia"
    echo "installed: $HOME/.local/bin/gubia -> $(pwd)/gubia"
    cp "config/agents.sh" "$HOME/.config/gubia/agents.sh"
    echo "installed: $HOME/.config/gubia/agents.sh"
    if ! command -v gubia >/dev/null 2>&1; then
        echo "warning: $HOME/.local/bin is not on your PATH; add it to invoke 'gubia' directly" >&2
    fi
