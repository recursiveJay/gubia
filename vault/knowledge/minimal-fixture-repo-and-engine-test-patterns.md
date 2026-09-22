---
name: minimal-fixture-repo-and-engine-test-patterns
description: "tests/fixtures/repo-minimal/ is the versioned fixture for gubia engine e2e tests (minimal plan + scripted fake CLI), with its usage pattern and the additional pattern for testing signal escalation on process-group shutdown."
type: methodology
---

# Minimal fixture repo and engine test patterns

## The versioned fixture `tests/fixtures/repo-minimal/`

For e2e tests of the `gubia` engine there is the versioned fixture
`tests/fixtures/repo-minimal/`: a minimal 3-subtask plan + a scripted fake
CLI `fake-cli.sh` + its own `config/agents.sh`. Consolidated pattern:

1. Copy the fixture to a tempdir with `cp -a` before running, and record
   that `stop.md` does not pre-exist in the copy
   (`tests/gubia_run_fixture_drain.bats:19-21` and `:82-84`).
2. Count loop turns with the fake CLI's external "tick" witness
   (`marker.log` with one line per turn; default `.fixture-log/` outside
   `.gubia/`, overridable with `GUBIA_FIXTURE_LOG`: `fake-cli.sh:23-25` and
   `:83-85`), never with the engine's internal counters.
3. With 3 subtasks drained the loop produces 4 ticks and the 5th no longer
   invokes the agent: the CLI's success signal does not stop the iteration,
   the turn that WOULD create the stop file creates it and it is checked
   when opening the next one (`gubia_run_fixture_drain.bats:109-116`).
4. Discriminate the TWO possible exit 0s of `gubia run` — stop file created
   vs `max_iteraciones reached` — with a grep of "stop file present" and a
   negated grep of "max_iteraciones reached", with an external `timeout 60`
   as a belt (`gubia_run_fixture_drain.bats:88-94`).
5. The judge can run the fake CLI from the real repo root without
   `GUBIA_ROOT`/`GUBIA_FIXTURE_LOG` and leave untracked artifacts
   (`.fixture-log/`); they are gitignored for the next checkpoints
   (`iteration-000374-20260829-222433.log:26-27`).

Never run tests against the repo's own `plan/plan.md`, which is being
drained by the loop in progress (`tests/fixtures/repo-minimal/README.md:7-11`).

### Fake CLI design: it does not interpret the prompt, it maps by file

The fixture's fake CLI (`tests/fixtures/repo-minimal/fake-cli.sh`) does NOT
interpret the content of the received prompt: it drains by reading the plan
from `GUBIA_PLAN` (relative to `GUBIA_ROOT`), both exported by the engine
into the iteration environment, just as a real agent navigating the repo
would. The prompt transport depends on the agent that invokes it: the
engine passes `prompt_file` as a positional argument to the catalog
function, and it is that function that wires it into its argv with its own
flag (`-p "@$prompt_file"` in omp, `--prompt-file` in devin). The fixture's
functions (`_fixture_agent`) ignore their arguments and do not wire the
prompt into `GUBIA_ARGV`, so the fake CLI rescues it from stdin or from
`--prompt <path>`/last argument for manual-use robustness. The content is
never interpreted in any case.

The per-iteration effect is mapped by the task file NAME (the subtask's
identity), never by the subtask's text — robust to rewordings. A task with
no mapped effect aborts with exit 1: it is the contractual signal of a
badly extended fixture, which the engine reads as an iteration failure and
rotates/aborts.

Whoever extends the fixture preserves this taxonomy (new tasks = new
entries in `apply_task`, deterministic effects, scripted exit codes and
mapping only by file name).

Evidence: `fake-cli.sh:10-14` ("ITS CONTENT IS NOT INTERPRETED…"), `:36-40`
("The task file's identity is the key of the mapping, never the subtask's
text"), `:44-49` ("the catalog function is the one that wires it into its
argv … as the probe's stdin") and `:17-18` ("Scripted exit codes: 0 =
iteration completed; 1 = invalid usage").

## TERM→KILL escalation test on process-group shutdown

To truly verify the TERM→KILL escalation of `invoke_agent`'s process-group
shutdown, a fake CLI whose direct child dies on the first `SIGTERM` is not
enough: you must build a fake CLI that spawns a **grandchild** that
explicitly ignores `SIGTERM` and stays in the same process group. Only then
does the test force the initial `kill -TERM -<PGID>` to be insufficient and
require the escalation `kill -KILL -<PGID>` to avoid leaving orphans.

Pattern used in the bats-core process-group shutdown test: the fake CLI
does `trap '' TERM` in the grandchild process and then sleeps; the test
checks that, after `invoke_agent`, no process of the original PGID is still
alive. This pattern is reusable for any future test that verifies
process-group management in `gubia`.
