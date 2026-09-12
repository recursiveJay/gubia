# scribe / consolidate

"consolidate" action: review the full set of `vault/conocimiento/` when it
has grown past 10 entries, and bring it back to ≤10 by pruning, merging,
relocating, or deleting — without losing knowledge with irreproducible
evidence just to shorten the list.

**Only applies in `vault/` mode.** In single-skill mode there is no
threshold equivalent (see `review.md`, "Chaining to `consolidate`"): if the
repo has no `vault/`, this action never fires, neither chained nor manually.

## Triggers

- Chained from `review.md` when, after applying its changes, the file count
  in `vault/conocimiento/` ends up >10.
- Manual invocation `/scribe consolidate` (requires an existing `vault/`; if
  it does not exist, abort with the literal message: "There is no `vault/`
  in this repo: `consolidate` does not apply, there is no file threshold to
  manage").

## Procedure

1. Read the full set of `vault/conocimiento/` (it is a bounded corpus — just
   over 10 files — so it is read directly, with no subagents in between).
2. For each entry, decide one of four actions:
   - **Merge**: two or more entries cover the same concern from different
     angles (e.g. two pitfalls of the same symptom) → a single entry that
     keeps all the evidence of both.
   - **Prune**: an entry became obsolete or irrelevant to the current state
     of the repo (check against the current code/plan before deciding; never
     prune just for age).
   - **Relocate**: an entry fits better as a section of an existing local
     skill than as a `vault/conocimiento/` entry (e.g. a procedure detail
     specific to a single skill, not cross-cutting project knowledge).
   - **Keep**: the entry is still cross-cutting, current knowledge with no
     overlap with another — leave it untouched.
3. Apply the decided changes:
   - Merge/prune/relocate: in **sequence**, one after another — unlike
     `review.md`, here the decisions are interdependent (merging A+B affects
     whether C still makes sense on its own), so they are not parallelized
     even when the destination is different files.
4. Verify that the final count of `vault/conocimiento/` is ≤10. If it is
   not, repeat step 2 on what remains before finishing.
5. Report in a direct summary what was merged, pruned, or relocated, and why.
6. If there are uncommitted changes that form a coherent block, create a
   commit with a concise message describing it.

## Hard rules

- Never prune an entry just to lower the count: every prune is justified by
  obsolescence verified against the current state of the repo, never by the
  need for room.
- Never lose evidence with an irreproducible observable symptom (a concrete
  log trace, a commit, a file line) when merging: the merged entry keeps the
  evidence of both source entries, not just the prose of one of them.
- It does not delegate to `forja`: it does not exist yet in this project.
- It does not implement product code.
