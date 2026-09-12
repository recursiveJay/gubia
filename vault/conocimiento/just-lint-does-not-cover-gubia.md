---
name: just-lint-does-not-cover-gubia
description: "just lint does not run shellcheck over gubia (no .sh extension); use scripts/lint-gubia.sh before accepting a lint regression that touches gubia."
type: pitfall
---

# Just lint does not cover gubia

`just lint` (defined in `justfile`) runs `find . -name '*.sh' | xargs -r shellcheck`.
The repo's main executable, `gubia`, has no `.sh` extension (it is a bash script
with a shebang but no suffix), so that `find` **never picks it up**. `just lint` can
finish green without having run shellcheck over `gubia` even once.

`scripts/lint-gubia.sh` covers the gap: it runs `just lint` and additionally
`shellcheck -x gubia` explicitly, exiting with a non-zero code if either one
fails. Before accepting the lint regression of a task that touches `gubia`, run
`scripts/lint-gubia.sh` instead of plain `just lint`.

It almost happened again in task 09: iteration 000352 reports `just lint` green
while the real tree state included the new test without shellcheck
("just lint exit 0" in `.ralph/logs/plan/iteration-000352-20260829-211550.log`).
First invoke lint with the variant that covers gubia, and don't trust a green
that only guarantees the files `find -name '*.sh'` finds.
