---
name: plan-x-state-unreliable-without-cross-check
description: "The surface [x] of plan.md or of a task checkbox is not sole evidence of work: it can come from two different actors or fall out of sync with the derived file; always cross-check against logs or against the internal file."
type: pitfall
---

Several distinct symptoms of the same underlying problem — the string of
`[x]` checkboxes is not a self-sufficient source of truth:

## Checkboxes with two different authors

The `- [x]` checkboxes in the task file have TWO authors following
distinct paths: the judge skill (`judge` action) marks them directly in
the file with its verdict, and the loop binary (`ralph-loop`) writes a
checkpoint after each `SUBTAREA_COMPLETADA`. Both reach `[x]` via
different routes, and the file can end up with marks from both
mechanisms mixed on the same line, with later commits dragging that
mix along (commit `0aefa89` docs(plan): close judge checkboxes and
regression in 09).

Symptom: a positive verdict recorded but the mark absent in the block's
commit, or `[x]` marks disappearing/appearing between plan commits with
no real work change. Cross-check against the iteration logs
(`.ralph/logs/plan/iteration-*.log`) if in doubt.

Evidence: `.ralph/logs/plan/iteration-000356-20260829-212135.log` and
`.ralph/logs/plan/iteration-000359-20260829-212451.log` (text: "Action
applied to the task file: - [x] at the [judge] checkpoint on line
51"); commit `0aefa89`.

## `plan.md` marked `[x]` while the derived file still holds `[ ]`

Task 10 of a previous plan ended up marked as done in `plan/plan.md`
with its entry `[x]` even though its derived file still held unmarked
`[ ]` subtasks — including the closing checkpoints (`[judge]`, and the
`maestro`/`forja` reviews inserted as the file's last subtasks). The
`/ralph chivato` reopened it with the note: "**Reopened by chivato**:
the plan marked this task as done but subtasks remained unmarked"
(`plan/plan/10.md:2-5`).

Symptom: the task's entry in `plan/plan.md` is `[x]` while the derived
file (`plan/plan/NN.md`) still holds `- [ ]` inside: the upward
propagation and the actual draining of the file did not match up.

## Judge rejection note cleared on re-mark

The judge's rejection annotation on a subtask line ("rejected by judge
(attempt N)") is cleared when the loop re-marks the subtask `[x]`, so
the judge's own escalation counter resets to attempt 1 and the rejection
never escalates. In task 03 the same literal-grep rejection recurred at
"attempt 1" twice (`.gubia/logs/25.out`, `.gubia/logs/28.out`) because
re-marking the subtask erased the previous verdict before the judge ran
again.

Symptom: a `[judge]` rejection repeats with "attempt 1" each time and
never accumulates; the rejection is invisible in the task file, only in
the iteration logs. Cross-check `.gubia/logs/*.out` for the judge's
rejection text, not the task file's annotations.

## Common rule

Do not consider a task done until ALL its pending checkpoints are
drained, including the closing reviews, which are not decoration but
the file's last subtasks. Cross-check the plan's `[x]` against the
task file's internal checkboxes before propagating upward, and do not
treat the string of checkboxes as sole evidence of work without
cross-checking logs when in doubt.

Evidence: `plan/plan/10.md:2-5` (cited above).
