# judge / instrument

Action "instrument": validate that a task file is fit to run unattended,
inserting the missing `[judge]` checkpoints (and the `[create evidence]`
entries needed before them) and editing the plan to remove any dependency on
human intervention. **It does not judge evidence**: it only evaluates
coverage and unattended execution. To judge, load `judge.md`.

## Five responsibilities

1. **Judge coverage**: after each implementation block with verifiable risk
   (observable output: binary, migration, endpoint, file, test, metric…)
   there must be a `[judge]`. It does not require a judge after purely
   declarative subtasks.
2. **Unattended execution**: no subtask asks for confirmation, waits for
   user input, delegates an automatable manual action, or introduces gates
   that only a human can lift. Reading existing configuration, using
   defaults, or failing deterministically is legitimate autonomy.
3. **Executable evidence available**: each `[judge]` that requires
   executable proof or a runtime property has its `[create evidence]` before
   it (the harness that makes it possible).
4. **Regression coverage**: only if the objective is a software repo with
   regression mechanisms (tests, test-ui, lint, type-check, build) and the
   file modifies code. Then: a test-update subtask and one
   `[judge regression]` per separable mechanism, with the command of the
   **full suite**, never scoped to what changed. Never duplicate a
   `[judge regression]` already present (e.g. those from `/gubia phase0`).
5. **Local evidence**: the criterion of each `[judge]` can be satisfied with
   what exists **at the point in the plan where that `[judge]` is**, not
   with what will exist at the end. A checkpoint that requires querying a
   service started in a later task, or using a fixture created by another
   file further on, is not assessable where it is: its criterion is
   rewritten to scope it to a local target, or the `[create evidence]` that
   makes its precondition local is placed before it. **Relocating it is not
   an option in v1**: moving a `[judge]` to another point in the plan
   requires knowing the preconditions left by the whole plan, which is the
   v2 graph.

## 9-step procedure

1. Read the whole task file.
2. Remove human intervention: rewrite any subtask that asks for
   confirmation, waits for input, or delegates an automatable manual action.
3. Identify the blocks with verifiable risk.
4. Check the existing judge coverage over those blocks.
5. Insert the missing `[judge]` entries, with the three fields from
   [`scaffold_task.md`](../gubia/scaffold_task.md): Scope, acceptance
   criterion, required evidence.
6. Insert the necessary `[create evidence]` entries when the harness for a
   `[judge]` that requires executable proof or a runtime property is
   missing.
7. Add regression coverage (test-update subtask + `[judge regression]` per
   separable mechanism) if the repo and the file qualify.
8. Touch nothing else: the only allowed edits are those of steps 2, 5, 6 and
   7. Do not mark, rename, reorder, or edit `[judge]` entries already
   present.
9. Save the file and confirm in conversation what was inserted or
   rewritten.

## Granularity

A `[judge]` closes the block of consecutive subtasks **whose evidence is
collected together**, and verifies a single concern. With several separable
concerns, several small `[judge]` entries. Rule of thumb: more than ~3
criteria that don't share evidence → split. The grouping criterion is the
shared evidence, **not thematic affinity**.

## Hard rules

- **Does not judge**: ignores the evidence even if there are prior `[x]`.
- **Does not infer progress from checkboxes**: an `[x]` is not enough; the
  plan must leave a verifiable trace.
- **Does not implement what's missing**: if a subtask is ambiguous, add a
  `[judge]` that forces evidence to be produced; do not rewrite it.
  Exception: the subtask that requires user intervention is rewritten (step
  2), but never to add code logic.
- **Edits the plan, not the code**: the rewrite affects only the plan text.
- **Does not duplicate, but does not over-group either**: merges only
  consecutive `[judge]` entries with exactly the same concern and evidence;
  never merges separable concerns.
- **One line per criterion and per evidence**: atomic bullets.
