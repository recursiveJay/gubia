# judge / judge

Action that verifies with reproducible evidence whether an implementation
block marked `[x]` satisfies its pending `[judge]`, acting directly on the
task file (never a verdict given in conversation alone).

## When it triggers

When there is a pending `[judge]` (or `[judge regression]`) whose Scope is
entirely `[x]`. Judges a single block per invocation.

## Key rules

- Three outcomes: **positive** (marks the `[judge]` as `[x]`), **negative**
  (unmarks the subtask and applies the rejection flow with an attempt
  counter, threshold 10, `[judge unblock]` on the 5th rejection, `stop.md`
  on the 10th), **not evaluable** (Case A: preparable environment missing →
  `[environment setup]`; Case B: harness missing → `[create evidence]`;
  Case C: unresolvable without a human → `stop.md`).
- Always re-runs the persistent evidence suite (previous `[create
  evidence]`) as a regression gate, though it does not re-inspect
  judgments already made.
- Rejections with counter N ≥ 3 escalate engine effort (`gubia effort set
  high`) and queue its restoration to medium.
- Literal comparison against the acceptance criterion, never
  interpretative.
- Does not implement product code or fix directly: it only rules on the
  task file.
- When escalating effort (`gubia effort set high`) from an automatic
  action, first check that `.gubia/state.env` and the engine exist; if
  they don't, don't invoke the command or create state (relevant when
  invoked in a workspace where `gubia` hasn't been initialized yet).
- When a subtask touches the engine's execution flow, require the full
  path to have been exercised in a real run (e.g. rerun of `gubia run`
  with a test agent), not just static code inspection or an isolated
  unit test: task 04 of the migration to `vault/` rejected three
  implementation subtasks for this exact reason (the execution
  subcommand never actually invoked the agent), documented literally in
  each rejection (`plan/plan/04.md:50-52`, `:54`).
- If the file count of a directory shared across tasks (e.g.
  `vault/conocimiento/`) doesn't match what the original migration task
  expected, don't reject on that alone: check whether a later `scribe`
  documented a legitimate consolidation (explicit pruning/relocation)
  before ruling — see also the warning about fragile count criteria in
  `instrument.md`. Evidence: `plan/task/06.md:61-66` (10 files instead of
  ~19, justified by the task 04 consolidation documented in
  `plan/task/04.md:63-70`).
