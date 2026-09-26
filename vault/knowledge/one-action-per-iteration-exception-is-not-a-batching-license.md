---
name: one-action-per-iteration-exception-is-not-a-batching-license
description: "The loop's one-action-per-iteration contract is broken when one iteration performs several real subtasks; the 'already done' skip exception only licenses marking work that already exists, not doing trivial work in bulk."
type: pitfall
---

The loop contract "each iteration executes one single action and stops" is
violated by treating a string of small/mechanical subtasks as one action. The
skip exception — which lets a single iteration mark several subtasks `[x]`
when inspection shows they are already done — does NOT extend to *performing*
several subtasks in one pass just because each is easy.

Symptom: a single `.out` reports finishing several real subtasks with fresh
edits in one iteration. Task 04's translation pass executed 5 subtasks
(validate context + 3 translate + the `bootstrap-phase0.sh` branch decision) in
one iteration (`.gubia/logs/34.out:3`), immediately after the prior iteration
had explicitly invoked the one-action rule to stop at a single subtask
(`.gubia/logs/33.out:3`). Iteration-boundary confusion of the same shape
recurred in task 03 (`.gubia/logs/32.out`).

A related failure is the **forward edit**: doing a *later* subtask's edit in
an earlier iteration but deliberately leaving it unmarked ("I'll let the next
iteration pick it up"), so the later subtask then resolves via the
"already done" skip with evidence that reads `already present`. Task 02's
catalog.md edit was applied in the `effort` iteration
(`.gubia/logs/11.out:3`) and only claimed two iterations later as
`already present` (`plan/task/02.md:41`). The edit was real work done out of
order, not pre-existing state — so the skip exception did not genuinely
apply to it.

Guidance: one iteration = one real subtask, done in order. Batch only `[x]`
marks for already-completed work, never fresh edits; if a run of subtasks is
genuinely trivial and atomic, split or order them so each iteration carries
one verifiable unit and its own `SUBTASK_COMPLETED=true`. Do not perform a
future subtask's edit early and leave it unmarked: claim it immediately (and
stop), or leave it untouched for its own iteration.
