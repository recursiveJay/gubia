---
name: verification-gates-need-the-repo-specific-invocation
description: "A task file's named verification gate (`just lint`, `bats tests/`) does not run as written in this repo — `just lint` skips `gubia` and bare `bats` is not on PATH — so name the repo's canonical gate (`scripts/lint-gubia.sh`, `just test`) instead of the generic command."
type: pitfall
---

Two scaffolded verification gates fail exactly as named, for different
reasons, and both are fixed the same way: name the repo's canonical
invocation rather than the generic command.

## `just lint` never checks `gubia`

`just lint` (defined in `justfile`) runs `find . … -type f -name '*.sh'
-print | xargs -r shellcheck -x` (pruning `.git` and `tests/vendor`). The
repo's main executable, `gubia`, has no `.sh` extension (it is a bash
script with a shebang but no suffix), so that `find` **never picks it up**.
`just lint` can finish green without having run shellcheck over `gubia`
even once.

`scripts/lint-gubia.sh` covers the gap: it runs `just lint` and additionally
`shellcheck -x gubia` explicitly, exiting with a non-zero code if either
one fails. Before accepting the lint regression of a task that touches
`gubia`, run `scripts/lint-gubia.sh` instead of plain `just lint`.

It happened in task 09 (`just lint` green while the tree carried the new
test without shellcheck — `.ralph/logs/plan/iteration-000352-20260829-211550.log`)
and recurred at plan-writing time in the fase-2 fix-a task (commit
`208482e`): the task file's Constraints and `[judge]` acceptance criterion
named `just lint` as the lint gate for a change that only touched `gubia`.

## Bare `bats` is not on PATH

Scaffolded task files and acceptance criteria name `bats tests/` as the
regression suite (e.g. `plan/task/01.md` "Regression suite: `bats tests/`",
`plan/task/03.md` "Required evidence: run `bats tests/` from the repo root").
But there is no `bats` on the PATH in this environment: the gate fails
immediately with `command not found: bats` (observed on the `[commit]`
iteration of `plan/task/01.md`, 2026-09-26).

The binary is vendored as a git submodule at
`tests/vendor/bats-core/bin/bats` (installed via `git submodule update --init
tests/vendor/bats-core`), and the canonical gate is `just test`
(`justfile:12-13`), which invokes it over `tests/*.bats` directly. To run a
single file without `just`, call the vendored binary by path:
`tests/vendor/bats-core/bin/bats tests/<file>.bats`.

## Common rule

When a task's Constraints or a `[judge]` acceptance criterion names a
verification command, write the repo's canonical gate
(`scripts/lint-gubia.sh` for lint over `gubia`, `just test` or the vendored
`tests/vendor/bats-core/bin/bats <file>` for tests), not the generic
`just lint`/`bats tests/` that under-covers or does not resolve. The green
result is identical; only the invocation differs.
