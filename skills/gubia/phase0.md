# gubia / phase0

Action `/gubia phase0`: break the plan (`plan/plan.md` by default) down into task
files, one per top-level task. **Phase 0 always runs inside the loop**: this
action doesn't break anything down by itself; it only materializes task 00 —the
reserved manifest that orchestrates the breakdown— and its link in the plan.
It's the engine, iteration by iteration draining `task/00.md`, that later
produces the breakdown, the simplification, the context validation, the
effort, the `[judge]` checkpoints, the cleanup, and the commits.

## Hard precondition

The plan (`plan/plan.md` by default) must exist. If it doesn't: abort without
creating or inferring it, and return the literal message:

> `plan/plan.md` doesn't exist. `/gubia phase0` doesn't create the plan, it only breaks it down.

This check runs in an isolated command (e.g. `test -f plan/plan.md` or
equivalent), never chained with other checks (`;`, `&&`, `||`) in the same
shell invocation: the exit code of a different command in the same chain must
not be attributed to the plan's existence.

## The only thing this action does

1. Check the hard precondition above.
2. Create or reconcile `task/00.md` (next to the plan file) as the reserved
   manifest, by running `scripts/bootstrap-phase0.sh <plan>` (materializes
   the manifest with its fixed subtasks; see "Task 00 contract").
3. Insert or fix the `- [ ] [00. Drain phase 0](task/00.md)` entry in the
   plan as the first item in the list, following the format of
   [`scaffold_plan.md`](scaffold_plan.md).
4. Finish.

It does nothing else: it doesn't drain any subtask of task 00, it doesn't
touch task 01 onward, it doesn't invoke the engine. The content of the
manifest's subtasks (breakdown, simplification, context validation, effort,
judge-instrument, cleanup, commits phases) is task 00's own contract; it
lives in `scripts/bootstrap-phase0.sh` and isn't repeated here.

## Task 00 contract

Task 00 is the reserved manifest that orchestrates the breakdown.
`scripts/bootstrap-phase0.sh` materializes it with these fixed subtasks, in
this order: Breakdown, Simplification, Context validation, Effort,
Judge-instrument, Cleanup, Commits.

The file must open with exactly this heading and this note, before any
subtask:

`# Task 00 — Drain phase 0`

`Mandatory header note: this reserved file (task 00)`
`only orchestrates breaking the plan down into product tasks. It's not a`
`product task and is excluded from simplification, context validation,`
`effort, judge-instrument, cleanup, and commits; a second phase0 pass`
`doesn't reprocess it either, nor reuse it as a product task.`

Task 00 is **excluded from all of phase 0's own work**: none of the later
phases reprocess it. Specifically, task 00 doesn't go through subtask
simplification, context validation, effort marks, `[judge]` planning, plan
file cleanup, or commit interleaving. That exemption is stable across later
passes too: if `phase0` is invoked again on a plan that already has task 00,
the reserved file isn't reprocessed or reused as a product task.

## If `task/00.md` already exists

This action is idempotent over the manifest, not a work trigger: it
reconciles the file and the link if needed, but doesn't run or "advance" any
of its subtasks. An interactive session never runs task 00's subtasks —
the next pending one in the manifest is named and the user is pointed to
`/gubia run` so the loop can drain it.

## Hard rules

- Tasks live in `task/`, next to the plan file; the path isn't derived from
  the plan's name, the link written in the plan is the only source of truth.
- No plan, no phase 0.
- No product work is run during this action.
