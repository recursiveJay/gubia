---
name: write-vault-against-live-code
description: "When creating or migrating vault/ documentation that describes live code, write against the source citing exact paths+lines and verify with grep that no references to destilado/ or referencia/ remain; when the doc is a reference layer (summary, not a copy), the [judge]'s acceptance criterion compares length/size against the source, not just an eyeballed content review; and when executing a task that cites file:line references to update, re-grep each one before editing — the inventory is a claim about the repo, not a fact; and, when executing a rename task of a migration plan, prefer an anchored-regex criterion over extra path exclusions when the surviving leftover is a hyphenated variant of the old name, and stage for the commit only the files the task touched, leaving unrelated working-tree drift unstaged."
type: methodology
---

The historical `destilado/` spec was out of date with respect to the current
code in at least five dimensions, verified while writing `vault/spec/` (task
03):

- `gubia` lines: ~550 → 2158;
- layers named in the script's header comment (`agents_`/`integrity_`) that
  **do not exist** in the code — the real ones are
  `state_`/`run_`/`invoke_`/`config_`;
- synchronized skills: 2 → 3 (`scribe` was missing);
- `agent_probe` omitted from the agent catalog;
- `install-config` absent from the installation documentation.

Copying `destilado/` literally would have propagated those errors into
`vault/`. The following procedure was applied successfully to the four
`vault/spec/` files (`engine.md`, `catalog.md`, `instalacion.md`, `README.md`)
and is reusable for any new `vault/` content:

1. Read the live source cited in the task (`gubia`, `config/agents.sh`,
   `justfile`, the skills…), **not** the historical spec.
2. Write in prose with exact paths and lines; no code dumps or extensive
   diffs.
3. Verify `grep -rl "destilado\|referencia/" vault/<dir>/` returns empty
   before considering a file done.
4. Cite as evidence the concrete confirmed paths+lines (e.g.
   `config/agents.sh:32`, `gubia:1938`), not unanchored counts.

## Reference layer verified by length, not content

When a task asks for a "summary, not a copy" reference layer over some
source files (e.g. `vault/skills/` summarizing `skills/`), the acceptance
criterion for the `[judge]` subtask should include a cheap, objective
metric in addition to the qualitative review: comparing the size/length of
each destination file against its source (`find` + line or byte count).

In the task that created `vault/skills/` (`plan/task/04.md`, lines 59-61),
the `[judge]` verified that the 8 reference files occupy between 20% and
40% of the length of their corresponding source file in `skills/`
(evidence: `.gubia/logs/19.out`, positive verdict citing that range).
Requiring this quantitative threshold, not just "it isn't a literal copy",
avoids accepting a "summary" that in practice reproduces nearly all of the
original content.

## The "no live references remain" grep must exclude the destination and files pending deletion

When this same kind of grep is used as the acceptance criterion of a
`[judge]` to confirm that no live references remain to something migrated or
in the process of being removed (not only when writing a new file, but when
reviewing the whole repo), excluding only the source being migrated/removed
is not enough: it yields false positives in two legitimate places that are
not the responsibility of the task in progress.

- The migration's **destination directory** (`vault/`), if it contains
  documentation that cites the old term for historical/descriptive purposes
  (narrating the migration itself) or reference copies that deliberately
  reproduce old rules from another file (e.g. `vault/skills/` documenting a
  rule the original has not yet lost).
- **Files pending deletion in a later task** of the same plan (not the one
  being executed now): while they exist, the grep finds them, but fixing or
  excluding them is not in scope of the current task (e.g. `persona-SKILL.md`,
  pending deletion in a later closing task).

When this happens, the `judge` skill does not treat it as a rejection of the
work ("Case A: negative"): it classifies it as "Case B: the harness is
missing" — the work may be fine, but the verification criterion is poorly
scoped. The fix is to insert a subtask that refines the evidence command
(adding the missing exclusions), not to repeat the reject/correct cycle of
the work itself.

Evidence: task 05 of the migration to `vault/` (`plan/task/05.md:114-141`);
the `[judge]` rejected the literal command of the original criterion
(excluding only `vault-migration.md`, `plan/` and `destilado/`) because it
returned matches in `persona-SKILL.md` and in out-of-scope `vault/`, and
inserted the `[create evidence]` subtask that added `--exclude-dir=vault` and
`--exclude=persona-SKILL.md` to the command.

A later `[judge]` checkpoint of the same plan that needs to repeat this same
kind of verification (e.g. a closing `[judge regression]` that re-checks "no
live references" over the whole repo) must **reuse literally** the command
already scoped and validated in the previous checkpoint, instead of
re-deriving the exclusions from scratch: the correct harness was already
fixed once, and reasoning it out again is repeated work that also risks
omitting an already-known exclusion. Evidence: task 06
(`plan/task/06.md:86-93`), whose `[judge regression]` reuses as-is the
command from task 05 (with `--exclude-dir=vault` and
`--exclude=persona-SKILL.md`) and only adds `--exclude-dir=.git`,
`--exclude-dir=destilado` and `--exclude=vault-migration.md` because the
closing scope is broader.

## The grep criterion must be scoped to the changed section, not the whole file

The same grep-as-judge-criterion pattern fails the other way too: a bare
`grep <phrase> <file>` over an entire file matches **unrelated** occurrences
of the phrase, rejecting work the change never touched. In task 03 the
criterion "`grep -n "isn't implemented" vault/spec/engine.md` returns
nothing" (meant to confirm the log-rotation gap note was gone) also matched
an integrity-detector note at `vault/spec/engine.md:80` ("That capability
isn't implemented in the live code"), forcing a spurious reword of unrelated
prose to "absent from the live code" (`plan/task/03.md:42`). The judge verdict
then oscillated PASS/FAIL across adjacent iterations as the loop re-marked the
subtask.

When writing a grep-based judge criterion, scope it to the section or line
range actually being changed (e.g. `vault/spec/engine.md:256-277`), never the
whole file — the same scoping lesson as the exclusion case above, from the
opposite side.

## A plan's reference inventory is a claim about the repo, not a fact

When a task hands over an explicit list of `file:line` references to update (a
rename or migration inventory), that list was grep-verified when the plan was
drafted; by the time the task is executed it can be stale. Re-grep every
cited reference **before** editing it, and treat the plan's inventory as a
hypothesis to confirm, not as a work order whose target is guaranteed to exist
in the form described.

A reference-update subtask whose target turns out not to carry the string is a
legitimate **no-op**: record the verified absence on the subtask line (command
plus its exit code) and move to the next one. Never invent the missing
reference, and never edit a file that does not carry the string, just to make
the subtask look fulfilled.

Evidence: `plan/task/01.md:12` — the plan asserted that
`skills/judge/judge.md:41` carried `vault/conocimiento/`; `grep -n conocimiento
skills/judge/judge.md` returned exit 1, while the only live judge-side
reference was the condensed mirror `vault/skills/judge/judge.md:41`. The
subtask was rewritten as an explicit no-op instead of fabricating an edit
(`.gubia/logs/9.out:7`).

## An anchored-regex criterion replaces path exclusions for hyphenated historical names

When the acceptance criterion of a `[judge]` is "no live reference to `X.md`
remains", the repo usually also carries *historical* names that merely begin
with the old stem (`motor-decisiones.md`, `motor-contrato.md`,
`catalogo-agentes.md`: trees that no longer exist on disk and whose mentions
must survive). A plain-substring grep (`conocimiento`, `motor`) matches those
too, so the criterion has to grow `:(exclude)` paths to stay green, whereas a
criterion anchored to the full filename as a regex (`motor\.md`,
`catalogo\.md`) cannot match a hyphenated sibling at all.

Prefer the anchored regex when what must survive is a hyphenated variant of
the old name: it keeps the evidence command short and makes the exclusion
reason unnecessary. Keep the path exclusions for leftovers that genuinely
contain the exact filename, because the regex cannot separate those.

Evidence: task 01's criterion was the plain substring `git grep -n
conocimiento` with three exclusions (`plan/task/01.md:41-44`); task 02's was
`git grep -nE 'motor\.md'` over the same three exclusions and no more, with
the reason stated literally in the task file (`plan/task/02.md:39`: "The
historical `motor-decisiones.md`/`motor-contrato.md` names do not match
`motor\.md`"), verified empty in `.gubia/logs/18.out:1`. Conversely, task 04
expects exactly one leftover because `destilado/instalacion.md` is cited from
a live note and does match `instalacion\.md`: there the regex buys nothing
and the leftover is handled as the "destination documentation" case above.

## The `[commit]` subtask commits what earlier iterations already staged

The phase-0 scaffold splits each rename into separate subtasks: the rename
plus its reference edits in one iteration, the `[judge]` checkpoint on the
staged tree in the next, and a `[commit]` subtask after it. Two consequences
repeat identically in every rename task of such a migration plan:

- The commit subtask finds the working tree already edited and staged; it
does not produce the edits. Do not re-apply or re-verify them there: stage
the rename's files as they stand (`plan/task/02.md:41`, evidence
`.gubia/logs/18.out:3` "staged", then `.gubia/logs/19.out:3` "were already
staged/edited from previous iterations").
- The working tree can carry drift unrelated to the migration, belonging to
the user (here a modified `config/agents.sh` model map). Stage explicitly the
files the task touched; never `git add -A` or `git commit -a`, which would
fold that drift into the rename's logical commit. Report it as deliberately
left unstaged.

Evidence: `plan/task/01.md:45` and `plan/task/02.md:41` state it on the
subtask line; `.gubia/logs/13.out:1` and `.gubia/logs/19.out:4` show both
rename commits of this phase leaving `config/agents.sh` out.
