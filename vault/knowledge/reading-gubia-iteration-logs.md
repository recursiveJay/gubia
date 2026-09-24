---
name: reading-gubia-iteration-logs
description: "How to correctly interpret a .gubia/logs/ iteration set: retention is ordered by mtime (never the numeric <iter> prefix, which restarts each relaunch and collides across runs), an empty .out is not by itself a failure, and any <iter>.* citation rots once loop_max_logs further iterations have run."
type: pitfall
---

Four facets of the same concern — reading a `.gubia/logs/` iteration set
without misdiagnosing it:

## Retention is ordered by mtime, never the numeric `<iter>` prefix

`.gubia/logs/` rotation keeps iteration sets ordered by modification time,
never by the numeric `<iter>` prefix. The prefix is local to each
`cmd_run` invocation (`gubia:1636`) and restarts at 1 on every relaunch,
so a `10.prompt` from an earlier run is older than a `1.prompt` from a
later run: numeric sorting would keep the wrong files across relaunches
(PRD R2). The always-written `<iter>.prompt` is the mtime anchor for a
set, because `run_prompt` writes it unconditionally every iteration
(`gubia:1110-1112`).

Do not re-introduce numeric-prefix ordering in any future log-retention or
ordering change; the cross-run collision is the observable symptom (older
run's high prefix outranking the newer run's low prefix).

## Retention is a hard horizon: a cited `<iter>.*` expires

Ordering by mtime says which sets survive; `loop_max_logs` says how many.
Beyond that count the sets are **deleted**, every suffix of each
(`prompt`/`out`/`err`/`console`) atomically and non-abortively
(`run_prune_logs`, `gubia:1563-1596`; `rm -f` guarded by `|| true` so a
broken prune never feeds the rotation streak). Only those four known
suffixes are touched: `.gitkeep` and future engine files survive. The
prune runs after every iteration (`gubia:1739`).

Consequence, which bites the knowledge corpus itself: any citation of the
form `.gubia/logs/<iter>.out` written into a committed `vault/knowledge/`
entry or a task file is a **short-lived** anchor. It expires once
`loop_max_logs` further iterations have run — within the same plan, not
only across relaunches — and then resolves to whatever unrelated iteration
later reused that number (the prefix collision above), or to nothing at
all. Observable symptom: a `[scribe]`/`[judge]` scout re-reading a
knowledge entry's `file:line` evidence finds a different incident at that
path, or a missing file.

Preventive rule: when distilling evidence into permanent knowledge, anchor
on things that do not rotate — the task file and its line, a commit hash, a
source `gubia:<line>` — and prefer citing the `<iter>` log only as
secondary colour, with the concrete quote inlined. When a `[scribe]` pass
finds an entry whose `<iter>` citations have already rotted, correct the
entry rather than reproducing the dead path.

Evidence for the horizon: `.gubia/state.env:6` (`loop_max_logs=20`) with
the retained corpus starting exactly at `.gubia/logs/34.*` while earlier
iterations of this same plan (e.g. the `9.out`/`18.out`/`19.out`/`28.out`/
`29.out` cited by `write-vault-against-live-code.md`) are gone. Evidence
for the rot already materialised: this entry's own former `14.out`/`14.err`
citations no longer resolve — `14.out` was then an unrelated `[scribe]`
output and `14.err` held only `Working...` (verified 2026-09-23, before
both were pruned away altogether).

## An empty `.out` with a usage-limit `.err` is not a real failure

If the `.out` of a gubia engine iteration comes out empty (no
`SUBTASK_COMPLETED=true` and no subtask marked) and the corresponding
`.err` contains an exhausted-usage-limit message from an LLM provider
(e.g. "You've hit your usage limit... try again at..."), do not interpret
this as a failure of the work itself or of the task file: it is an
external quota exhaustion, outside the execution. The next relevant
iteration resumes the first pending `[ ]` subtask without any problem, with
no `[regression fix]` mark and no manual intervention (observed during the
migration to `vault/`, task `plan/task/04.md`). Do not create a repair
subtask or a regression checkpoint for this symptom.

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
`SUBTASK_COMPLETED=true` in `.out`, or carries its failure text there.

In this repo every `.err` of a run holds the CLI's progress line alone
(`Working...` in iterations 5-25), so the absence of a provider error in
`.err` says nothing about the work.

Evidence: iteration 25 of this plan (task `plan/task/03.md`, the `[scribe]`
subtask). Observed from inside that same invocation: `25.prompt` at
00:01:59.153, `25.out` 0 bytes at 00:01:59.154, `25.err` 11 bytes
(`Working...`) at 00:01:59.919 — while the iteration was still running. It
was the newest set (iteration 24 had closed at 00:01:44) and it never
produced a failure record.
