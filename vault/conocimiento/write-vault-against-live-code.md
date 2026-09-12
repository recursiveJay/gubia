---
name: write-vault-against-live-code
description: When creating or migrating vault/ documentation that describes live code, write against the source citing exact paths+lines and verify with grep that no references to destilado/ or referencia/ remain; never copy literally from the historical spec without verifying every fact.
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
`vault/spec/` files (`motor.md`, `catalogo.md`, `instalacion.md`, `README.md`)
and is reusable for any new `vault/` content:

1. Read the live source cited in the task (`gubia`, `config/agents.sh`,
   `justfile`, the skills…), **not** the historical spec.
2. Write in prose with exact paths and lines; no code dumps or extensive
   diffs.
3. Verify `grep -rl "destilado\|referencia/" vault/<dir>/` returns empty
   before considering a file done.
4. Cite as evidence the concrete confirmed paths+lines (e.g.
   `config/agents.sh:32`, `gubia:1938`), not unanchored counts.

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
