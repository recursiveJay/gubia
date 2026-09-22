# Fixture `repo-minimal`

Self-contained synthetic repository for the e2e tests of task 10
(plan/10.md): `gubia run` launched over its plan must drain all the
subtasks and create `stop.md` next to it, with no human intervention.

It is the versioned version of the temporary repo that the e2e tests of
tasks 04-06 assemble by hand (`mktemp -d` + `config/agents.sh` + fake CLI):
the tests copy it to a temporary directory, point `GUBIA_AGENTS_SH` at its
catalog and launch the engine against its plan — never against the
`plan/plan.md` of the repo itself, which is being drained by the loop in
progress.

## Structure

- `plan/plan.md` — test plan with three linked tasks.
- `plan/task/00.md`, `01.md`, `02.md` — task files, each with one trivial
  deterministic subtask.
- `fake-cli.sh` — fake agent CLI with scripted exit codes (sibling of the
  ones in the e2e suites of tasks 04-06); the contract is in its header.
- `config/agents.sh` — minimal catalog: the four agent functions that
  `gubia config validate` requires (`agent_probe` included), the
  model/fallback arrays of the three levels, and the `agent_probe` that
  drains the plan pointing at the fake CLI by absolute path.

## Fake CLI contract

One invocation = one iteration of the contract (`motor-contrato.md`) over
the fixture's plan:

1. Signs a `tick` line in `$GUBIA_FIXTURE_LOG/marker.log` (or
   `.fixture-log/`): the tests count loop turns by counting lines.
2. Drains ONE subtask (`[x]` + evidence in the task, propagation to the
   plan when the task is exhausted) applying the effect mapped by file name
   (`greeting.txt`, `output/echo.txt`, `done.flag`).
3. No pending items in any task: creates `plan/stop.md` (step 1 of the
   contract).
4. Emits `SUBTAREA_COMPLETADA=true`. Exit 0 on completion; 1 on invalid
   usage.

The prompt arrives via argv (path of the file the engine composes, `file`
mode), but its content is NOT interpreted: the plan is read from
`GUBIA_PLAN`/`GUBIA_ROOT` (exported by the engine to the iteration), just
as a real agent navigating the repo would.

## Usage (from a bats test)

```bash
repo="$(mktemp -d)"
cp -a tests/fixtures/repo-minimal/. "$repo"/
cd "$repo"
home="$(mktemp -d)"   # installs skills gubia/judge in whatever layout applies
GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
  "$GUBIA_BIN" config validate           # preflight green
GUBIA_AGENTS_SH="$repo/config/agents.sh" HOME="$home" \
  "$GUBIA_BIN" run plan/plan.md 10       # drains and stops via stop file
```

The `gubia` binary is taken from the real repo (`GUBIA_BIN` of the test
itself); the fixture contains no copy of the engine.
