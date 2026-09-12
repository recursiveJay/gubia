# Task file — scaffold

Structure of a product task file (`task/NN.md`, from `01.md` onward, next to the plan file). It's materialized by the breakdown phase of task 00 (see `gubia-phase0.md`); it's read by the implementer of each iteration and by the `judge` skill. The manifest `00.md` doesn't follow this scaffold: it's materialized by `scripts/bootstrap-phase0.sh`.

## Scaffold

```markdown
# Task NN — <concise title>

## Objective

<one or two sentences stating what condition is satisfied once this is done>

## Linked context

- <links to repo files, documents, other tasks, relevant prior decisions>

## Constraints

- <hard rules to respect: paths, forbidden libraries, compatibility>
- <regression suite command(s), if the repo has them>

## Happy path (small example)

<brief, concrete description of what the system looks like working after the task; no code>

## Subtasks

- [ ] [effort <low|medium|high>] Fix the model's capability: run `gubia effort set <level>`.
- [ ] Validate the linked context of this file against the repo's current state; if it's stale, update the affected sections before continuing.
- [ ] <implementation subtasks for the first block>
- [ ] [judge] <checkpoint title>
  - Scope: <the implementation subtasks it closes>
  - Acceptance criterion: <literal and checkable: exit 0, exact string, row count>
  - Required evidence: <exact command to run, or file to read>
- [ ] <subtasks for the next block, with its own [judge]>
- [ ] [scribe] Distill the learning accumulated from this task.
```

## Structural rules

- **Five sections, in this order**: `Objective`, `Linked context`, `Constraints`, `Happy path`, `Subtasks`.
- **First bullet `[effort …]`, second the context validation** (only in product task files `01.md`+; manifest `00.md` is excluded from effort marks). The effort one is prepended by the effort phase, not the breakdown.
- **No code**: no snippets, no diffs, no long commands. References by path + description. The exception is the evidence commands inside a `[judge]`, which are the evidence itself.
- **Real paths, never assumed conventions**: verify where the repo's documentation/code actually lives before naming paths.
- **Concrete and verifiable subtasks, never qualitative**: ❌ "check quality", ✅ "ensure `/healthz` responds 200 in < 300 ms under `scripts/load_healthz.sh`".
- **No human intervention**: no subtask may ask for confirmation, wait for input, or introduce a gate that only a human can lift.
- **Every subtask fits in one iteration**: the simplification phase splits any that don't.
- **Review closure: `[judge]` and `[scribe]`, nothing else.** Verification blocks close with `[judge]` (and `[judge regression]` if applicable); the whole file closes with `[scribe]` as the last subtask, always after the last `[judge]`. There are no `chivato`, `maestro review`, or `forja review` bullets.

## The `[judge]` checkpoint

A `[judge]` always carries three fields, the ones `judge-judge.md` reads literally:

- **Scope**: the implementation subtasks it closes. The judge only acts once they're all `[x]`.
- **Acceptance criterion**: checkable **literally**, not interpretively. If the repo already had failing tests, list them so the criterion only requires that no previously-passing test turns failing.
- **Required evidence**: the exact command or the file to read. In a `[judge regression]`, the command for the **full suite**, never scoped to what changed.

**One per block whose evidence is collected together.** The grouping criterion is shared evidence, not topical affinity (see `judge-instrument.md`): a `[judge]` that mixes separable concerns forces collecting evidence for everything at once, and its symptom is the judge getting stuck or doing shallow work.

**Its criterion must be satisfiable at the point in the plan where it sits** — local evidence. If it requires something that will only exist later, the criterion is scoped down or a `[create evidence]` is prepended to it; in v1 there's no relocating checkpoints.

## Pitfalls

- **Fan-out as a context bomb**: a bullet "do X in every file of <set>" that doesn't fit in one iteration. If the set is enumerable at phase 0, expand it into one bullet per element; if it's dynamic, model it as a draining loop with a persistent manifest (`[create evidence]` that builds it + a self-perpetuating subtask + a `[judge]` that verifies zero pending).
- **`[effort …]` as an inline tag** attached to a content subtask: that subtask runs with the **old** model, because the engine reloads `state.env` at the start of the next iteration. It must be an independent subtask.
- **Literal grep over markdown text that will be written later**: fragile against wording variation. Quote the exact fragment in the writing subtask.
- **Paths invented out of habit**: writing "document in `docs/`" when the repo uses `vault/` creates a parallel directory nobody reads.
