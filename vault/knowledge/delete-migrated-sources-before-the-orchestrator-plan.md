---
name: delete-migrated-sources-before-the-orchestrator-plan
description: In a closing task that deletes several obsolete paths of a migration, including the plan that orchestrates it, the plan is always deleted last and only after the rest of the subtasks (including any verification [judge]).
type: decision
---

# Delete migrated sources before the orchestrator plan

When a closing task deletes both the already-migrated sources (historical
spec, temporary distillation files) and the plan itself that orchestrated
the migration, order matters: the sources are deleted first, one by one,
and the plan (plan file + task files, itself included) is deleted
**last**, as the final action of the last subtask.

Reason: as long as the plan exists, it remains the only reliable reference
for which subtasks — including any verification `[judge]` or
`[judge regression]` — remain to be closed. Deleting it too early removes
that reference, and if a later verification were to fail, there would be
nowhere to reopen the task or record the rejection. That's why the
constraint is stated explicitly in the task file itself, not inferred from
the scaffold.

Evidence: `plan/task/06.md:28-33` — "`persona-SKILL.md` is deleted before
`destilado/`, and both before touching `plan/`... The deletion of `plan/`
must not run until the rest of this task's subtasks (including the
verification `[judge]`) are closed." The task file's own subtask sequence
reflects this literally: delete `persona-SKILL.md` → delete `destilado/` →
`[judge]` → `[judge regression]` → commit → `[scribe]` → delete `plan/`
(the only subtask after `[scribe]`).

Generalizes to any closing task with this shape (delete N sources + the
orchestrator itself): order by decreasing reversibility, leaving for last
whatever, once deleted, prevents verifying or fixing a failure in the
previous steps.
