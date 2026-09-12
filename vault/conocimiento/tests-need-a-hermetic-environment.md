---
name: tests-need-a-hermetic-environment
description: "Two ways to contaminate a test with the developer's real environment (untrimmed PATH, real $HOME) that break assertions or pollute the machine; both require isolating the environment before running, not relying on PATH order."
type: pitfall
---

Two incidents of the same underlying problem — a test that assumes
isolation from the real environment without enforcing it:

## Untrimmed fake PATH does not hide real host binaries

Simulating a binary's presence in a test with `PATH="$fakebin:$PATH"` does
not simulate the absence of the rest: the host's real binaries (claude,
devin, omp in `~/.local/bin`) remain on the PATH and break the
"not detected" assertions. Fix: trim to a minimal PATH without them,
`PATH="$fakebin:/usr/bin:/bin"`, and check beforehand that no relevant
binary lives in the trimmed set.

Observable symptom: negative assertions that fail only on the developer's
host and pass in CI or other hosts without those binaries.

Evidence: `.ralph/logs/plan/iteration-000355-20260829-211940.log` (text:
"with PATH="$fakebin:$PATH" the real binaries on this machine (claude,
devin, omp in ~/.local/bin) leaked through and broke the negative
assertions. Fix: PATH="$fakebin:/usr/bin:/bin""), committed in `990a39d`.

## Installer test against the real `$HOME` pollutes the machine

A test exercised the `sync-skills` target of the `justfile` against the
real `$HOME` (installed `judge` in the devin and omp locales, re-synced
`~/.claude/skills/gubia` and `judge`). The following iteration was spent
entirely restoring: re-installing gubia/judge from `skills/` and deleting
the devin and omp directories that had been created.

Observable symptom: logs with the text "Restored — ~/.claude/skills/gubia
and judge are back (re-synced from repo...". Evidence:
`.ralph/logs/plan/iteration-000350-20260829-211410.log` (startup, the
restoration), and `git log --oneline -- tests/` up to `648f087`.

## Common rule

Any skills-installer test must be born with a temporary `$HOME` (mktemp) +
PATH with stubs, and `! -e` verified paths; pattern committed in
`tests/sync_skills_overwrite.bats` and
`tests/sync_skills_detects_present_harnesses.bats`.
