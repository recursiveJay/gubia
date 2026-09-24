# scribe / consolidate

"Consolidate" action: when `vault/knowledge/` exceeds 10 entries, brings
it back down to ≤10 by merging, pruning, or relocating — without losing
irreplaceable evidence just to shorten the list. Only applies in `vault/`
mode; single-skill mode has no equivalent threshold and this action never
fires.

## When it fires

Chained from `review.md` when the count exceeds 10 after its changes; or
manual invocation `/scribe consolidate` (aborts if `vault/` doesn't exist).

## Key rules

- For each entry, decide one of four actions: merge (same symptom from
  different angles), prune (obsolete, verified against the current repo —
  never just by age), relocate (fits better in a local skill), or keep.
- Apply changes in sequence, never in parallel: the decisions are
  interdependent.
- Never prunes just to lower the count; never loses irreplaceable evidence
  when merging — keeps it from both source entries.
- Doesn't implement product code. Only writes under `vault/knowledge/`.
