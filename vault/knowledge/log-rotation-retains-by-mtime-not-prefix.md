---
name: log-rotation-retains-by-mtime-not-prefix
description: Why .gubia/logs/ rotation orders iteration sets by mtime, never the numeric <iter> prefix, and the cross-relaunch collision numeric ordering would produce.
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
