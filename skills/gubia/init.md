# gubia / init

Action `/gubia init`: materialize `plan/plan.md` (by default) from the
scaffold when a human wants to start a gubia loop but isn't sure how to
draft the objective, or suspects there's scattered context around the
repo that should be linked from the plan. **Optional use**: nothing
forces going through here; anyone who already knows what they want can
write `plan/plan.md` by hand and launch `/gubia phase0` directly.

This action is only invoked explicitly by the user — it never appears in
`SKILL.md`'s proactive detection. Deciding whether someone "isn't sure
how to draft the objective" is too speculative a judgment to trigger on
its own; unlike phase0's structural check (are there unchecked tasks?),
there's no objective signal in the repo to justify it here.

## Hard precondition

The plan (by default `plan/plan.md`) must **not** exist. If it already
does: abort without touching it, and return the literal message:

> `plan/plan.md` already exists. `/gubia init` does not overwrite an
> existing plan; edit it by hand or delete it first if you want to
> restart.

This check runs in an isolated command (e.g. `test -f plan/plan.md`),
never chained with other checks in the same shell invocation.

## The only thing this action does

1. Check the hard precondition above.
2. Ask the user what they want to do and what minimal context they can
   give (see "Gathering intent").
3. Scan the repo for relevant written context (see "Context scan") and
   read, in a bounded way, the candidates that look critical.
4. Draft a brief objective and a list of linked context, and write
   `plan/plan.md` following `scaffold_plan.md`.
5. Inform the user, in a direct and concise summary, of what was
   written (drafted objective + context sources used + gaps detected,
   if any), and suggest `/gubia phase0` as the next step.

It does nothing else: it doesn't create task files, doesn't touch
`task/`, doesn't invoke the engine or `/gubia phase0` on its own.

## Gathering intent

Open free-text question — never predefined options, a plan's objective
isn't a closed choice — about two things at once: what the user wants to
achieve, and what minimal relevant context they can directly provide
(documents, decisions already made, constraints).

If the answer is too terse to sketch an objective (one or two words, no
context at all), ask again **once**, specifically requesting what's
missing. After that retry, proceed with what's available — never an
indefinite loop of questions — and the gap is declared in the final
report in step 5.

## Context scan

### Candidates (deterministic part, delegated to a script)

`scripts/scan-init-context.sh [root-directory]` (defaults to cwd) lists,
without reading content, the files that are candidates for containing
relevant written context:

- Walks the full tree from the root, excluding `.git/`, `node_modules/`,
  `vendor/`, `dist/`, `build/`, `.venv/`, `target/`. Uses `fd` if
  installed; otherwise falls back to `find`. (Preferring `rg` for name
  filtering is out of scope for v1 if it complicates the script too
  much — `grep`/string comparison in bash is enough here since only the
  base name of each file is compared, no content search.)
- Filters by name (without extension), case-insensitive substring match
  against `{prd, spec, rfc, design, readme, index}`, plus any file under
  a `vault/` or `docs/` directory that didn't already match above.
- Restricted to plain-text extensions (`.md`, `.txt`, `.rst`) or no
  extension (like `README`): an `index.html` or `spec.pdf` doesn't
  count — they aren't readable with `head` and would only waste tokens
  in the report.
- Returns each candidate as `<category>\t<path>`, already sorted by
  reading priority: `index` (readme/index) first, then `keyword`
  (prd/spec/rfc/design), then `docdir` (vault/docs without a name
  match).

### Reading (interpretive part, done by the agent)

Over the list the script returns, the agent reads (`head`, 10-20 lines)
at most **8-10 candidates**, in the priority order already given by the
script:

1. First the `index` ones (readme/index): they help locate more
   pointers if the repo uses progressive disclosure (an index that
   links to the actual documents, instead of having them scattered).
2. Then the `keyword` ones.
3. `docdir` ones are only read if there's still room left in the cap
   after exhausting the two previous categories.

If the objective and context are already reasonably clear before
exhausting the cap, stop early — no need to read all 8-10 if 2 or 3 are
enough.

### When to ask the user again

Ask again for additional context (once, same as in "Gathering intent")
when:

- The scan finds no candidates, or
- It finds some, but in the agent's judgment the content read doesn't
  plausibly cover the objective the user stated.

If after that follow-up the context is still insufficient, proceed
anyway: the plan is written with what's available, and the final report
explicitly states what remains weak or assumed, so the human can fix it
by hand before `/gubia phase0`.

## Writing the plan

Follows the structure of [`scaffold_plan.md`](scaffold_plan.md):

- **`## Objective`**: a few lines, drafted by the agent from what the
  user said and what was read in the scan.
- **`## Context`**: one entry per source actually used to draft the
  objective (not everything scanned, only what contributed), as
  `- [relative/path](relative/path) — what it contributes in one
  sentence`. Real paths from the repo, never invented.
- **`## Tasks`**: the scaffold placeholder is left intact
  (`- [ ] [00. Task title](task/00.md)`) — untouched; `/gubia phase0`
  overwrites it when materializing task 00.

Writing is direct, with no prior confirmation gate: the user isn't shown
a draft to approve before writing. The report in step 5 comes after
writing and describes what's already saved in `plan/plan.md`, so the
user can fix it by hand if something doesn't fit before continuing.

## Hard rules

- No explicit invocation, no `init`: never suggested or launched on its
  own initiative.
- No prior plan: if `plan/plan.md` already exists, abort without
  overwriting.
- No confirmation gate before writing: it writes and then reports,
  never the other way around.
- Maximum one retry question to the user, both in "Gathering intent"
  and in "when to ask again" in the scan: never an indefinite loop of
  questions.
- Cap of 8-10 candidates read: scanning names is cheap, reading isn't.
- `## Tasks` isn't touched and nothing is created under `task/`: that's
  `/gubia phase0`'s job.
- `/gubia phase0` isn't launched on its own: it's only suggested, same
  as the existing rule for phase0 → run.
