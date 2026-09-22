---
name: log-rotation-retains-by-mtime-not-prefix
description: Why .gubia/logs/ rotation orders iteration sets by mtime, never the numeric <iter> prefix, the cross-relaunch collision numeric ordering would produce, and how far retention reaches (beyond loop_max_logs every set is deleted, so a citation to <iter>.* expires within the same run).
type: decision
---

Retention of `.gubia/logs/` iteration sets is ordered by modification time,
never by the numeric `<iter>` prefix. The prefix is `local` to each `cmd_run`
invocation (`gubia:1636`) and restarts at 1 on every relaunch, so a
`10.prompt` from an earlier run is older than a `1.prompt` from a later run:
numeric sorting would keep the wrong files across relaunches (PRD R2). The
always-written `<iter>.prompt` is the mtime anchor for a set, because
`run_prompt` writes it unconditionally every iteration (`gubia:1110-1112`).

Do not re-introduce numeric-prefix ordering in any future log-retention or
ordering change; the cross-run collision is the observable symptom (older
run's high prefix outranking the newer run's low prefix).

## Retention is a hard horizon, not a floor: a cited `<iter>.*` expires

Ordering by mtime says which sets survive; `loop_max_logs` says how many.
Beyond that count the sets are **deleted**, every suffix of each
(`prompt`/`out`/`err`/`console`) atomically and non-abortively
(`run_prune_logs`, `gubia:1563-1596`; `rm -f` guarded by `|| true` so a broken
prune never feeds the rotation streak). Only those four known suffixes are
touched: `.gitkeep` and future engine files survive. The prune runs after
every iteration (`gubia:1739`).

Consequence, which bites the knowledge corpus itself: any citation of the form
`.gubia/logs/<iter>.out` written into a committed `vault/knowledge/` entry or
a task file is a **short-lived** anchor. It expires once `loop_max_logs`
further iterations have run — within the same plan, not only across
relaunches — and then resolves to whatever unrelated iteration later reused
that number (the prefix collision above), or to nothing at all.

Observable symptom: a `[scribe]`/`[judge]` scout re-reading a knowledge
entry's `file:line` evidence finds a different incident at that path, or a
missing file.

Preventive rule: when distilling evidence into permanent knowledge, anchor on
things that do not rotate — the task file and its line, a commit hash, a
source `gubia:<line>` — and prefer citing the `<iter>` log only as secondary
colour, with the concrete quote inlined. When a `[scribe]` pass finds an
entry whose `<iter>` citations have already rotted, correct the entry rather
than reproducing the dead path.

Evidence for the horizon: `.gubia/state.env:6` (`loop_max_logs=20`) with the
retained corpus starting exactly at `.gubia/logs/34.*` while earlier
iterations of this same plan (e.g. the `9.out`/`18.out`/`19.out`/`28.out`/
`29.out` cited by `write-vault-against-live-code.md`) are gone. Evidence for
the rot already materialised: `external-usage-limit-leaves-an-empty-iteration-not-a-real-failure.md:17-23`
records that its own former `14.out`/`14.err` citations no longer resolve —
`14.out` is now an unrelated `[scribe]` output and `14.err` holds only
`Working...`.
