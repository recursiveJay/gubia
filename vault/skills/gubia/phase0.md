# gubia / phase0

Action `/gubia phase0`: breaks the plan (`plan/plan.md` by default) down
into task files, but only materializes **task 00** — the reserved
manifest that orchestrates the breakdown, via
`scripts/bootstrap-phase0.sh` — and its entry in the plan. The actual
breakdown of the following tasks is done later by the engine, iteration
by iteration, draining task 00's fixed subtasks (Breakdown,
Simplification, Context validation, Effort, Judge-instrument, Cleanup,
Commits).

## Key rules

- Hard precondition: if the plan doesn't exist, abort without creating
  it.
- Idempotent on the manifest: if `task/00.md` already exists, reconcile
  but don't execute or advance any of its subtasks.
- Task 00 is permanently excluded from simplification, context
  validation, effort, judge-instrument, cleanup and commits — including
  on later passes of `phase0` over the same plan.
- Doesn't execute product work during this action; an interactive
  session limits itself to naming the next pending subtask and pointing
  to `/gubia run` to drain it.
