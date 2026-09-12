# judge / instrument

Action that validates that a task file is fit for unattended execution:
inserts any missing `[judge]` and `[create evidence]` checkpoints and
removes any dependency on human intervention. Does not judge evidence
(that's `judge.md`'s job).

## When it triggers

When planning or reviewing a task file before the engine executes it, to
guarantee checkpoint coverage.

## Five responsibilities

Judge coverage after each block with verifiable risk, unattended
execution (no confirmations or manual gates), executable evidence
available before each `[judge]` that requires it, regression coverage
(`[judge regression]` per separable mechanism when the repo and file
qualify) and local evidence (each `[judge]`'s criterion must be
satisfiable with what exists at that point in the plan, not with future
preconditions; relocating a `[judge]` is not an option in v1).

## Key rules

- Does not judge: ignores whether there are previous `[x]`, only
  evaluates coverage.
- Does not implement what's missing: when in doubt, adds a `[judge]` that
  forces evidence, except for the one allowed rewrite (removing human
  intervention).
- Only edits the task file, never the code.
- One `[judge]` per concern with shared evidence; more than ~3 criteria
  without common evidence → split into several.
- Be careful when drafting a criterion that compares a file count in a
  directory shared across plan tasks (e.g. "as many `.md` as source
  sections"): another task may write to that same directory before or
  during execution and break the count without the work being
  incomplete. Compare against a subset identifiable by name, not against
  the directory's total.
