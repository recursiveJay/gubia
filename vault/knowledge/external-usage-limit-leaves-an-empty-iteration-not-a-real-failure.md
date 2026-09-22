---
name: external-usage-limit-leaves-an-empty-iteration-not-a-real-failure
description: an empty .out from a gubia iteration alongside a .err with a usage-limit error from the underlying LLM provider is not a regression of the work; the engine resumes on its own in the next iteration; and an empty .out with no diagnostic at all in .err is also what the iteration you are currently running looks like from inside it, so check the set's mtime and content before calling it a failure
type: pitfall
---

# External usage limit leaves an empty iteration, not a real failure

If the `.out` of a gubia engine iteration comes out empty (no
`SUBTAREA_COMPLETADA=true` and no subtask marked) and the corresponding
`.err` contains an exhausted-usage-limit message from an LLM provider
(e.g. "You've hit your usage limit... try again at..."), do not interpret
this as a failure of the work itself or of the task file: it is an
external quota exhaustion, outside the execution.

Evidence: during the migration to `vault/` (task `plan/task/04.md`), the
iteration `.gubia/logs/14.out` came out empty while `14.err` showed that
Codex quota error. The next relevant iteration (`.gubia/logs/15.out`)
resumed the first pending `[ ]` subtask without any problem, with no
`[regression fix]` mark and no manual intervention. Caveat verified
2026-09-23: the `<iter>` prefixes of `.gubia/logs/` are reused on every
relaunch (see `log-rotation-retains-by-mtime-not-prefix.md`), so those
concrete citations no longer resolve to that incident — the `14.out`
present in the corpus is 1655 bytes of task 01's `[scribe]` output and
`14.err` holds only `Working...`. Treat any `<iter>` citation as run-scoped:
re-check the set's mtime and content before relying on it.

Do not create a repair subtask or a regression checkpoint for this
symptom: it is enough to let the next loop iteration resume the subtask
from where it left off.

## An empty `.out` is also what the running iteration looks like from inside it

An empty `.out` is not by itself evidence of failure: the loop creates it
empty at launch (it is the redirection target of the agent's stdout) and it
stays empty until the agent yields its final answer, at the very end of the
invocation. Any diagnosis made *during* the iteration — including a
subagent reading `.gubia/logs/` for the LOGS/PLAN/INVENTORY findings of a
`[scribe]` pass — therefore always observes the current set as "empty
`.out`, `.err` with no diagnostic", which is exactly the shape of the
failure it is looking for.

Discriminate by mtime, not by content: if the `.prompt`/`.out`/`.err` of
the set are the newest in `.gubia/logs/` and their timestamps sit seconds
apart (`.prompt` written by `run_prompt`, then `.out`/`.err` created at
launch), the iteration is in flight. A finished iteration ends with
`SUBTAREA_COMPLETADA=true` in `.out`, or carries its failure text there.

In this repo every `.err` of a run holds the CLI's progress line alone
(`Working...` in iterations 5-25), so the absence of a provider error in
`.err` says nothing about the work.

Evidence: iteration 25 of this plan (task `plan/task/03.md`, the `[scribe]`
subtask). Observed from inside that same invocation: `25.prompt` at
00:01:59.153, `25.out` 0 bytes at 00:01:59.154, `25.err` 11 bytes
(`Working...`) at 00:01:59.919 — while the iteration was still running
(checked at 00:06). It was the newest set (iteration 24 had closed at
00:01:44) and it never produced a failure record.
