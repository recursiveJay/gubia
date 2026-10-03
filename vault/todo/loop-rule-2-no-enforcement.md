---
area: engine
kind: fix
---

# Loop contract rule 2 ("one subtask per iteration") has no structural enforcement

> An agent silently broke rule 2 by doing a later subtask's edit ahead of turn; nothing
> in the engine detects or flags it, and the skip exception cannot tell loop-made state
> from pre-existing state.

## Problem

The engine's per-iteration contract (`vault/spec/engine.md`,
"Contract injected per iteration") states five rules verbatim, rule 2 being
"execute a single subtask per iteration, with the bounded exception of work
already done (max 3 skips with nameable evidence)." This is pure-text,
self-reported: the engine "doesn't check off boxes… doesn't write to the
plan," and — critically — the historical integrity detector that would
snapshot the working tree before/after each iteration and flag `[ ]`→`[x]`
transitions outside a contiguous prefix "is absent from the live code…The
loop trusts the `SUBTASK_COMPLETED=true` token and the judge to catch
improper skips," with the detector explicitly deferred to v1.1/v2. There is
today no mechanism, structural or contractual, that stops (or even flags) an
agent from doing a *different* subtask's real edit inside the iteration it
is nominally spending on another subtask.

## Root cause

Verified against a real run, 2026-09-26; specifics kept generic here — this
pitfall will recur in unrelated future loops with their own logs and tasks,
so it is described by pattern, not by incident.

An iteration's active subtask was some unit of work `A`. The agent completed
`A`, marked it `[x]`, emitted `SUBTASK_COMPLETED=true` — **and, in the same
iteration, also performed the real edit belonging to a later subtask `B`**,
deliberately leaving `B` unmarked with the stated intent of letting a future
iteration "pick it up." Some iterations later, the iteration whose active
subtask actually was `B` resolved it by citing the "already done" skip
exception, reporting evidence that the change was `already present` —
because from that iteration's point of view the change genuinely was
already on disk. It had no way, and no instruction, to check *whether it had
gotten there through the loop's own prior, unmarked work* rather than
through pre-existing repo state.

This is two compounding failures, not one:

1. **Rule 2 was violated at the source iteration itself**: it performed
   two real units of work (the marked subtask plus an unmarked edit) while
   reporting only one `SUBTASK_COMPLETED=true`. No signal caught this
   because nothing compares the iteration's actual diff against the scope
   of its declared active subtask.
2. **The skip exception has no way to distinguish "pre-existing state" from
   "uncommitted state the loop itself produced two iterations ago."** A
   later iteration treating any on-disk match as skip-eligible evidence is
   exactly the gap: an uncommitted, dirty working tree *inside a running
   loop* is far more likely to be the loop's own unmarked prior work than
   something a human left behind, yet the contract gives no instruction to
   check for that before writing `already present`.

## Done when


- `vault/spec/engine.md`'s contract rule 2 (and the fixed header text the
  engine actually injects, `gubia:508` `run_contract_header`) is reworded to
  close the loophole explicitly: the "already done" skip exception licenses
  only *marking* `[x]` for state that predates the current loop run: an
  iteration must never perform a subtask's real edit ahead of turn and defer
  marking it "for the next iteration to pick up" — if work is done, its
  owning subtask is claimed and the iteration stops there, in the same
  iteration; if it isn't the active subtask, the edit is not made at all.
- Before an iteration writes `already present`/skip evidence for a subtask,
  the contract requires it to check whether the matching state is
  **committed** (predates this run, safe to skip) or **uncommitted in the
  working tree** (very likely produced by this same running loop; must not
  be skip-evidence — the iteration instead traces which prior iteration
  produced it and treats the contract as already broken, surfacing it rather
  than papering over it with a skip).
- A lightweight version of the historical integrity detector — the one
  already planned for v1.1/v2 per `vault/spec/engine.md` — is pulled forward
  to v1 in **warning-only** mode: a snapshot of `git status --porcelain`
  before and after each iteration, diffed against the active subtask's
  declared scope (file paths named in `Linked context`, when present), with
  a stderr/log warning (not an abort) when the iteration's diff touches
  files outside that scope. This is the mechanism that would have caught the
  observed case mechanically instead of relying on the agent's own honesty in
  its log line.
- `vault/knowledge/one-action-per-iteration-exception-is-not-a-batching-license.md`
  is updated once the contract wording lands: its "forward edit" section
  currently documents the symptom; it should note that the fix moved the
  guidance from vault-knowledge-only into the engine-injected contract
  itself, so it's enforced (or at least flagged) for every future loop run,
  not just remembered by whichever model reads the vault next.
- Verified by a fixture run (`tests/gubia_run_fixture_drain.bats` or a new
  sibling fixture) that reproduces the exact shape — an iteration whose
  agent edits a file outside its declared subtask and defers the mark — and
  asserts the warning fires.
