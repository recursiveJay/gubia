# judge / judge

Action "judge": verify with reproducible evidence that a previous
implementation block was carried out correctly before continuing with the
next one. It's the heart of the skill: it emits pass, fail, or "not
assessable" acting directly on the task file, with no verdict left in the
conversation.

## Triggers

- There are `[x]` implementation subtasks with a pending `[judge]` (or
  `[judge regression]`) after them.
- **One block per invocation**: the first pending `[judge]` whose Scope is
  entirely `[x]`. It stops whether it passes or fails; subsequent `[judge]`
  entries are judged by later invocations.

## Procedure

1. Locate the first pending `[judge]` checkpoint whose Scope is fully `[x]`.
2. Collect its evidence: run the commands or read the files under "Required
   evidence", capturing the output verbatim.
3. Re-run the entire accumulated persistent evidence suite (the prior
   `[create evidence]` blocks) as a regression gate.
4. Compare evidence and suite against the acceptance criterion
   **literally** (exit 0, exact string, row count), never interpretively.
5. Emit one of the three outcomes and take the corresponding action on the
   task file.

## Three mutually exclusive outcomes

- **Pass** — evidence collected and everything passes (criterion and
  persistent suite). Marks the `[judge]` as `[x]`.
- **Fail** — evidence collected and something fails (the criterion or a
  regression in the persistent suite). Unchecks the implementation subtask
  and applies the rejection flow with a counter.
- **Not assessable** — the evidence could not be collected. Distinguish why
  (see "Not assessable: three cases") and resolve without declaring a
  blockage, except in Case C.

## Rejection flow with attempt counter

- Feedback always goes on the unchecked implementation subtask, never on the
  `[judge]` line, as a suffix `— rejected by judge (attempt N): <one
  line>`. One line, no technical detail, code, paths, or commands.
- The counter N increments on each successive rejection of the same block.
- **Threshold of 10 rejections.**
- **On the 5th rejection**: insert `[judge unblock]` before the blocked
  `[judge]`.
- **On the 10th rejection**: create the stop file `stop.md` next to the plan
  (the same signal the agent creates when the plan is exhausted; the plan
  is not renamed).
- Outside the 5th and 10th rejections, no ordinary rejection creates the
  stop file or touches any file other than the task file itself.

## Effort escalation

- Any rejection whose resulting counter is N ≥ 3 raises the effort level:
  invoke `gubia effort set high`.
- On the same rejection, queue a `[effort medium]` bullet behind the
  `[judge]` to restore the level. The judge only requests the level change;
  it does not reimplement writing `state.env` (`gubia effort set` also
  resets `model_index`, and that is the engine's responsibility). The
  engine's loop restores the level when it reaches that bullet, not the
  judge.
- Resetting the in-process streak sentinel of `run` is also the engine's
  responsibility, not this action's.
- **Only if `.gubia/state.env` and the engine exist**: if they don't,
  `gubia effort set` is not invoked and no state is touched or created.

## Persistent evidence suite

- The `[create evidence]` entries produce persistent, committed,
  deterministic tests that form the file's suite.
- The already-verified inspection of a previous `[judge]` is not re-run; the
  full persistent suite is re-run on every `[judge]`, as a regression gate.
- A regression detected in the persistent suite is a fail for the current
  block, even if the failure lies in evidence from a previous block.

## `[judge regression]` checkpoints

- Gate over the repo's native mechanisms (tests, test-ui, lint, type-check,
  build). The **full suite** is always run, never a subset scoped to what
  changed.
- On failure, insert `[regression fix]` instead of rejecting the block
  directly.
- If the `[regression fix]` was already attempted and the regression
  persists, apply the ordinary rejection flow on that `[regression fix]`
  subtask (counter toward 10), instead of inserting another fix task.

## Not assessable: three cases

Distinguish why evidence can't be collected, with guards against loops:
never a second preparation/creation subtask for the same `[judge]`.

- **Case A — preparable environment**: something reproducible is missing
  (variable, local service, installable dependency). Insert
  `[environment preparation]`.
- **Case B — missing harness**: the executable evidence needed doesn't
  exist (the corresponding `[create evidence]` was never created or is
  insufficient). Insert `[create evidence]`. A failure attributable to code
  outside the block's Scope is not a fail for this block; it's Case B.
- **Case C — unresolvable without a human**: no autonomous action can
  produce the evidence (credentials, external access, product decision).
  Create the stop file `stop.md` next to the plan.

## Hard rules

- One block per invocation: never chain several blocks in the same run.
- Feedback only on the implementation subtask, never on the `[judge]` line.
- Does not re-inspect, but does re-run the entire persistent suite on every
  `[judge]`.
- Does not validate by soft heuristic: a previous `[x]`, a small diff, or an
  informal read do not substitute for the executor's termination token or
  for feedback persisted to the file.
- Runtime properties are not judged by reading code: they require an
  executable harness; without a harness it's Case B, not a fail.
- Full suite always in `[judge regression]`: scoping to changed
  tests/code is forbidden.
- Stop file exclusive to Case C and the 10th rejection: never on ordinary
  fails or Cases A/B.
- Does not implement product code: gaps are reflected as feedback,
  checkpoints, or diagnostics, never as a direct fix.
