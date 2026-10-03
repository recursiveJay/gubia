# Effort placement (`[effort …]` subtasks)

Spec of how phase 0 places `[effort low|medium|high]` subtasks in product
task files. Until now the placement depended on each model's judgment; this
spec makes it deterministic: a script computes it from the subtasks' text
and the model only reviews what the script could not classify.

## Background (live facts)

- `gubia effort set <level>` writes `effort_level` and resets `model_index`
  in `.gubia/state.env`. The level is **global and persistent**: it holds
  until the next `[effort …]`, across task files too (`engine.md`,
  "Consistency when changing effort level").
- An `[effort …]` must be a standalone subtask, never an inline tag: the
  engine reloads `state.env` at the start of the next iteration, so an
  inline tag makes its own subtask run with the old model
  (`skills/gubia/scaffold_task.md`, Pitfalls).
- `skills/judge/judge.md` ("Effort escalation") already raises to `high` on
  the 3rd+ rejection and queues an `[effort medium]` behind the `[judge]`.
  That mechanism is **not** touched by this spec and runs mid-drain, never
  in phase 0.
- Today the Effort subtask of `task/00.md` is a one-liner in
  `skills/gubia/scripts/bootstrap-phase0.sh`, with no rules, and runs
  *before* Judge planning and Commits, so it cannot see those subtasks.

## Decisions

### Model: transitions, not per-subtask levels

The analysis script computes the desired level of every pending subtask,
then collapses consecutive equal levels into **transitions**: "before
subtask *n*, `[effort X]`". The model only turns each transition into the
standalone bullet `- [ ] [effort X] Fix the model's capability: run \`gubia effort set X\`.`
It never invents transitions.

### Scripts (in `skills/gubia/scripts/`)

**`effort-plan.sh <task/NN.md> [--apply]`**

- Inspects only first-level `- [ ]` subtasks. Ignores `[x]` bullets,
  indented lines (Scope, Acceptance criterion…) and continuation lines of a
  multi-line bullet; matching uses the first line of the bullet only.
- Default mode is **read-only** and prints TSV, one transition per line:
  `<n>\t<level>\t<reason>`, where `n` counts only the `- [ ]` bullets and
  the insertion point is "before bullet *n*". Example:

  ```
  0	medium	initial (floor: context validation)
  5	high	before [judge]
  7	medium	restore: next=implement
  9	low	scaffold
  ```

- Subtasks matching no keyword inherit the previous level and are listed
  under a trailing `# unmatched` section so the model can review them. If
  there is no keyword at all, everything stays at the initial level and no
  further transitions are emitted. A file without any `[judge]` is not a
  special case.
- `--apply` inserts the bullets, idempotently: it deletes the `[effort …]`
  bullets already in the file and recomputes. It **aborts without touching
  anything** if any content bullet of the file is already `[x]` (phase 0
  precondition: the engine has not started draining it).

**`effort-expand-00.sh`** (a separate script, not a mode of the other)

- Appends to `task/00.md`, right after the Effort subtask, one bullet per
  product task file `01..NN` (numeric order): "Interleave effort subtasks
  for `task/NN.md`". Idempotent: it does not duplicate bullets already
  present.
- Does not process any task file itself and does not mark anything.

### Level rules

The keyword table is an array in the header of `effort-plan.sh`, the single
source of truth. Matching is whole-word, case-insensitive, on the bullet's
first line, in English (plans and `scripts/check-language.sh` are English).
When several keywords match, the highest level wins.

| Level | Keywords |
|---|---|
| `high` | `[judge*]` (judge, regression, unblock…), design, architect, refactor, migrate, investigate, debug, root cause, concurrency, race, security |
| `medium` | implement, add, fix, update, write/create test, document, `[create evidence]`, `[scribe]` |
| `low` | scaffold, rename, move, delete, remove, format, lint, bump, stub, commit |

- A subtask with no match **inherits** the previous level.
- `[judge*]` is one prefix: a `[judge unblock]` followed by a `[judge]`
  needs no bullet between them. After a `[judge]`, the level is restored to
  that of the next content subtask (no bullet if it is already equal).
- `[scribe]` is `medium`, and it is always the last subtask.
- A commit subtask is `low` only when its title is a commit.

### Initial bullet

`state.env` is global, so when `NN.md` starts, the level is whatever
`NN-1.md` left, and the script cannot know it (each file is processed in an
isolated iteration). Therefore the script **always emits** a first
`[effort X]` per file. `X` is the level of the first content subtask with a
floor of `medium`, since the first subtask is always the context validation
(reading and comparing, not cheap work). If content starts at `low`, the
next transition `medium → low` follows immediately.

Consequently the fixed first `[effort <level>]` bullet is **removed** from
`scaffold_task.md`: the breakdown no longer writes it.

### Flow in `task/00.md`

New order of the manifest: Breakdown, Simplification, Context validation,
Judge planning, Commits, **Effort**, Cleanup. Effort moves after Judge
planning and Commits because the script needs the `[judge]` checkpoints
(rule: `high` before each) and the commit subtasks (`low`) to already exist.

The iteration that drains the Effort subtask runs `effort-expand-00.sh`
and then marks the subtask `[x]`. The generated per-file bullets are then
drained **serially**, one per iteration, each with a clean context: the
model runs `effort-plan.sh --apply` on that file, reviews `# unmatched`,
and marks the bullet `[x]`. No subagents, no parallelism.

Task 00 itself stays excluded from effort marks, as today.

### Where the instructions live

- `skills/gubia/effort.md` (new): instructions for the per-file bullet
  (run the script, review `# unmatched`, what to do on abort).
- `bootstrap-phase0.sh` bullets only point to the script and to
  `effort.md`; `phase0.md` keeps saying the manifest's contract lives in
  the bootstrap and only updates the order.

### Out of scope

- Parallelizing phase 0 (recorded in `vault/todo/parallelize-phase-0.md`).
- Changing `judge.md`'s effort escalation.
- Re-running `--apply` mid-drain.

## Files affected

| File | Change |
|---|---|
| `skills/gubia/scripts/effort-plan.sh` | new |
| `skills/gubia/scripts/effort-expand-00.sh` | new |
| `skills/gubia/effort.md` | new |
| `skills/gubia/scripts/bootstrap-phase0.sh` | reorder subtasks, rewrite Effort bullet |
| `skills/gubia/phase0.md` | new manifest order |
| `skills/gubia/scaffold_task.md` | remove the fixed first `[effort …]` bullet and its rule |
| `vault/skills/gubia/phase0.md` | sync the documentary mirror (it already differs from `skills/`) |
| `tests/gubia_effort_plan.bats` | new, plus any existing test that depends on the manifest order |
| `vault/todo/parallelize-phase-0.md` | entry: parallelize phase 0 |
