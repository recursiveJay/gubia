# judge / unblock

Action "unblock": diagnose why a block accumulates rejections and, if the
loop is chasing an unreachable criterion as currently stated, document the
problem and its solution in the task file and insert an implementation
subtask for the fix before the blocked `[judge]`. **It does not
implement**: it only diagnoses, documents, and inserts the task.

## Triggers

- There is a pending `[judge unblock]` subtask `[ ]` (inserted by
  `judge.md` on the fifth rejection, right before the blocked `[judge]`).
  It is the highest-priority action among the three automatic ones.

## Procedure

1. Locate the pending `[judge unblock]` subtask and the blocked `[judge]`
   that follows it: its Scope, acceptance criterion, required evidence, and
   the rejection history accumulated on the implementation subtasks.
2. First check whether the blockage comes from a break of the progress
   contract (missing termination token, a token that doesn't propagate,
   persisted feedback that contradicts the closure). Name it if so: it's
   not a dubious heuristic, it's a real problem.
3. Gather context: read the plan file (objective and position of the
   block), the task file, and the harness/evidence code directly; delegate
   reading `.gubia/logs/` to subagents that return only the distilled
   conclusion (the failing command, the exact output signature, whether the
   failure is identical across iterations, whether the harness measures
   something other than the criterion).
4. Answer the binary diagnostic question: is the criterion reachable as
   currently stated and evaluated?
5. If unreachable, apply Action A. If reachable, apply Action B. When in
   doubt, treat as Action B.
6. Mark `[judge unblock]` as `[x]` and stop the loop.

## Binary reachability diagnosis

- **Unreachable**: the harness measures a different magnitude than the
  criterion asks for, the criterion contradicts itself, it demands a
  capability absent from the environment, or the evidence always fails for
  the same reason unrelated to the implementation.
- **Reachable**: the failure is attributable to the implementation
  delivered so far; a different implementer (or the same one, with another
  attempt) could satisfy the criterion as stated.

## Action A — unreachable

- Write a detailed diagnostic block, headed
  `## Loop diagnosis (judge unblock) — <block>`, with the problem anchored
  in concrete evidence (output signature, log line, harness code) and an
  actionable solution.
- Insert, before the blocked `[judge]`, an implementation subtask for the
  described fix.
- If the fix requires correcting a mis-stated criterion or evidence, adjust
  the blocked `[judge]` itself — the only exception to the rule of not
  touching already-present `[judge]` entries.
- Do not uncheck the original implementation subtasks if their rejection
  was spurious (the problem was in the harness or the criterion, not in
  them).

## Action B — reachable

- Writes no diagnostic and inserts no fix subtask.
- Unchecks to `[ ]` the block's implementation subtasks, keeping the suffix
  with the rejection history, so the ordinary reject/retry cycle continues.

## Hard rules

- Does not implement code, neither product nor harness: it only writes the
  diagnostic, inserts the fix subtask and, where applicable (Action A),
  adjusts the blocked `[judge]`'s criterion/evidence.
- Edits only the block's task file: never the plan file nor other task
  files.
- Logs via subagents: never load whole `.gubia/logs/` into its own context;
  subagents return only distilled conclusions.
- Every claim in the diagnostic is anchored in something read (output
  signature, log line, harness code) — never in conjecture.
- One unblock per block: after marking `[judge unblock]` as `[x]`, no other
  is inserted for the same `[judge]`.
- **Stop file exclusive to Case C and the 10th rejection** (managed by
  `judge.md`): this action never creates `stop.md`, neither in Action A nor
  in Action B.

## Pitfalls (with observable symptom)

- **Backticks in shell**: putting markdown with backticks inside
  double-quoted arguments when searching over logs makes the shell
  interpret them as command substitution. Symptom: `command not found`,
  `No such file or directory`, or accidental expansion. Use single quotes,
  escape the backticks, or `rg -F -e '...'`.
- **Confusing a mis-stated harness with a defective implementation**: the
  typical case is limiting the virtual address space with `RLIMIT_AS`
  (`ulimit -v`) to check an RSS cap, which produces SIGSEGV from engines
  like DuckDB/Arrow instead of a real OOM. Symptom: the failure is
  identical across iterations even though the implementer changed the code
  — a strong signal that the problem is not where it's being rejected.
- **Fabricating a dubious fix without sufficient evidence**: when in doubt,
  treat as Action B and let the cycle continue; the tenth rejection already
  forces human intervention.
