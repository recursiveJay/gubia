---
name: write-vault-against-live-code
description: "When writing vault/ documentation that describes live code, write against the source citing exact paths+lines, never copy an older spec; when the doc is a reference layer (summary, not a copy), the [judge] compares length against the source; a plan's file:line inventory, grep-based criteria and pinned match counts are claims about the repo at drafting time — re-verify and scope them at execution time; fan-out subtasks are split into single-iteration chunks; a [commit] subtask stages what the working tree actually carries, never `git add -A`; an accent-character class needs a UTF-8 locale."
type: methodology
---

## Write against the live source, not an older spec

An older spec of the same code drifts: line counts, layer names, the list of
synchronized skills, the agent catalog and the installation steps all went
stale in at least five places in the one that was checked. Copying it
literally propagates those errors into `vault/`. Procedure:

1. Read the live source cited in the task (`gubia`, `config/agents.sh`,
   `justfile`, the skills…), **not** the older doc.
2. Write in prose with exact paths and lines; no code dumps or extensive
   diffs.
3. Grep that no reference to the retired doc remains before considering a
   file done.
4. Cite as evidence concrete confirmed paths+lines (e.g.
   `config/agents.sh:32`), not unanchored counts.

## Reference layer verified by length, not content

When a task asks for a "summary, not a copy" layer over some source files
(e.g. `vault/skills/` summarizing `skills/`), the `[judge]` acceptance
criterion should include a cheap objective metric besides the qualitative
review: compare the size of each destination file against its source (`find`
+ line or byte count). In the task that created `vault/skills/` the 8
reference files came out at 20%–40% of their source's length. Requiring the
threshold avoids accepting a "summary" that reproduces nearly everything.

## A "no live references remain" grep must exclude the destination and files pending deletion

Excluding only the source being removed gives false positives in two
legitimate places that are not the current task's responsibility:

- The migration's **destination directory** (`vault/`), when it cites the old
  term to narrate history or holds reference copies that deliberately
  reproduce old rules.
- **Files pending deletion in a later task** of the same plan.

The `judge` skill does not treat this as a rejection of the work ("Case A:
negative"): it is "Case B: the harness is missing" — the verification
criterion is poorly scoped. Insert a subtask that refines the evidence
command (adding the missing exclusions) instead of repeating the
reject/correct cycle. A later checkpoint re-checking the same thing (e.g. a
closing `[judge regression]`) reuses the already-validated command literally
and only widens it if its scope is broader.

## Scope the grep criterion to the changed section, not the whole file

A bare `grep <phrase> <file>` over a whole file also matches unrelated
occurrences, rejecting work the change never touched (and forcing a spurious
reword of unrelated prose; the verdict may oscillate PASS/FAIL as the loop
re-marks the subtask). Scope it to the line range being changed (e.g.
`vault/spec/engine.md:256-277`).

## A plan's reference inventory is a claim about the repo, not a fact

An explicit list of `file:line` references to update was grep-verified when
the plan was drafted; by execution time it can be stale. Re-grep each cited
reference **before** editing it. A target that no longer carries the string
is a legitimate **no-op**: record the verified absence on the subtask line
(command plus exit code) and move on. Never invent the missing reference or
edit a file just to look fulfilled.

## Anchored regex over path exclusions for hyphenated historical names

When the criterion is "no live reference to `X.md` remains" and the repo also
carries historical names that merely begin with the old stem
(`motor-decisiones.md`…), a plain-substring grep matches them too and needs
`:(exclude)` paths. A regex anchored to the full filename (`motor\.md`)
cannot match a hyphenated sibling, so the command stays short. Keep path
exclusions for leftovers that contain the exact filename.

## A pinned expected count goes stale like a reference inventory

A criterion such as "returns exactly one line" is a drafting-time claim;
later commits (including scribe distillations) can legitimately add a match.
Refine the number in the task file *before* the `[judge]` runs, stating the
source of the new match on the same line, so the judge verifies the corrected
number and the edit stays auditable. Symptom of the opposite: a subtask
edited backwards — removing a legitimate surviving match — just to reach the
pinned count.

## Split a fan-out inventory subtask into chunks before the loop runs it

A reference-repoint subtask with tens of sites (e.g. 43 citations) spans far
more than one iteration and collides with the loop's "already done"
exception: verifying each site as already-done burns the 3-consecutive-skip
budget and stalls the loop. Split it during the phase-0 simplification pass
into chunks of one iteration each (43 became 11/11/11/10), keeping the
per-chunk line ranges explicit on each subtask line.

## The `[commit]` subtask commits what earlier iterations already staged

The scaffold splits a rename into the edit iteration, the `[judge]`
checkpoint on the staged tree, and a `[commit]` subtask after it:

- The commit subtask finds the tree already edited and staged; do not
  re-apply or re-verify the edits there, just stage the rename's files as
  they stand.
- The tree can carry unrelated drift belonging to the user (e.g. a modified
  `config/agents.sh` model map). Stage explicit files; never `git add -A` or
  `git commit -a`. Report the drift as deliberately left unstaged.

The explicit path list on the subtask line is itself a plan-time claim and
can under-specify the touched set (one rename found two extra files carrying
the same repoints). The authoritative set is `git status`/`git diff`: stage
every file that actually carries the change and record the deviation on the
subtask line.

## An accent-character class needs a UTF-8 locale, or it matches bytes

A class such as `[áéíóúüñÁÉÍÓÚÜÑ¿¡]` matches the intended characters only if
the matcher decodes UTF-8. Under the default `LC_ALL=C`, `grep`/`git grep`
treat it as a **byte set**, so `≥`, `≠`, `≤`, `§`, the em-dash and emoji
false-positive; an "accent sweep" reports dozens of lines with no Spanish
accent (one run: ~40 byte-mode hits vs 4 genuine lines).

Fix before trusting the count: `export LC_ALL=C.UTF-8`, or use a UTF-8-aware
matcher (`grep -P '(*UTF)[…]'`, or a Python scan decoding as UTF-8). Then
classify each surviving hit by hand, never by the raw number.
