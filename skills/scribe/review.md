# scribe / review

Action "review": distill the accumulated learning of a completed task — what
worked, which pitfall recurred, which local decision was made and why — into
reusable knowledge for the tasks that follow. It launches three read-only
subagents in parallel that return **findings with evidence, never synthesis**:
the synthesis (deduplicate, classify, create/extend/delete) is done by
`review` itself, not by the subagents.

## Triggers

- Pending `[scribe]` subtask `[ ]`, last in the task file, with everything
  before it in `[x]`.
- Manual invocation `/scribe review`.

## Step 0 — decide destination

Repeated on every invocation, never assumed from a previous pass:

1. `test -d vault/` at the workspace root.
2. If it exists → destination is `vault/conocimiento/` (one entry = one file).
3. If it does not exist → destination is the single skill,
   `skills/<root-repo-directory-name>/SKILL.md` (one entry = one `##` section
   in that single file). If the file does not exist yet, it is created with
   the minimal header (`name`, `description` in frontmatter, a `# <name>` and
   a sentence explaining that it is the distilled knowledge of the project).

## Step 1 — three read-only subagents, in parallel

Each returns a list of findings with anchored evidence (path + line, or a
literal quote); none interprets or summarizes beyond reporting what it found.

### LOGS

Reads `.gubia/logs/*.out` (and `*.err` when the corresponding `.out` is empty
or the content indicates failure), from most recent iteration to oldest.
Filters by relevance by grepping the content for the path of the task file
being closed. The engine prunes `.gubia/logs/` after each iteration to the
`loop_max_logs` most-recent iteration log sets, ordered by modification time
(not by numeric prefix, which collides across relaunches) — so there is no
need to impose an additional cap: read everything there is that is relevant.
Reports: what was attempted, what failed and why (if there is textual
evidence), which pattern recurred across iterations.

### PLAN

Reads the plan file and the task files of the block being closed (the path is
given by the plan link itself, a directory is never assumed). Reports:
`[judge]` rejections with their reason, subtasks inserted outside the original
scaffold (`[judge unblock]`, `[environment setup]`, `[create evidence]`,
`[regression fix]`...) and why, and decisions documented explicitly in the
task file itself (context sections, reopening notes).

### INVENTORY

Reads the already-existing knowledge: `vault/conocimiento/` or the single
skill (according to what Step 0 decides), plus any loose local skill in the
repository (skills under `skills/` that are not the engine itself — `gubia`,
`judge`, `scribe`). Reports the current inventory: which entries exist, of
what type, and what they cover — so that Step 2 can deduplicate against what
is already written.

## Step 2 — synthesis (done by `review`, not the subagents)

With the three sets of findings:

1. Deduplicate: the same finding may appear in LOGS and PLAN at once; it is
   treated as one.
2. Contrast against INVENTORY: if there is already an entry covering the
   finding, it is discarded or marked as a candidate to extend (not to
   create).
3. Classify each surviving finding into exactly one of:
   - **create**: new knowledge, with no prior entry covering it.
   - **extend**: an existing entry needs a precision, a new case, or a
     correction of a datum that became obsolete.
   - **delete**: an existing entry is no longer true or was contradicted by
     the finding itself (e.g. a documented pitfall that this task proves no
     longer applies).
4. Each *create* entry follows the format block corresponding to the
   destination (see "Format of an entry", below). One single concern per
   entry — never mix a pitfall and a decision in the same one.

## Step 3 — builder subagents

One per change approved in Step 2, which applies literally that creation,
extension or deletion on the destination file:

- **`vault/` mode**: builders run **in parallel** — each entry is its own
  file, there is no write collision.
- **Single-skill mode**: builders run **in sequence**, one after another —
  all entries live in the same `SKILL.md` and launching concurrent edits on
  the same file can overwrite each other.

## Step 4 — report and commit

1. Report in a direct summary what was created, extended or deleted (and
   where), without repeating the full content of each entry.
2. If there are uncommitted changes that form a coherent block of finished
   work (the knowledge entries touched in this pass), create a commit with a
   concise message describing it. It does not depend on any commit subtask of
   the task file: `[scribe]` runs after the last commit interleaved by the
   scaffold, so its own changes are not committed by anyone else.
3. Mark `[scribe]` as `[x]` in the task file.

## Chaining to `consolidate`

After Step 3, if the destination decided in Step 0 is `vault/` **and** the
file count in `vault/conocimiento/` ends up **>10** after applying the
changes of this pass, `consolidate.md` is loaded next, **in the same
invocation** — no new marker is queued and no other iteration is awaited. If
the destination is the single skill, this check is skipped entirely: there is
no threshold equivalent in single-skill mode.

## Format of an entry

### `vault/` mode (`vault/conocimiento/<kebab-case-name>.md`)

```markdown
---
name: <kebab-case-name>
description: <one line — what it is for and when to consult it>
type: methodology | pitfall | decision
---

<the reusable knowledge: the methodology to follow, the pitfall to avoid
(with its observable symptom), or the local decision made and its why.
Concise, actionable, one single concern per file.>
```

### Single-skill mode (`##` section in `skills/<name>/SKILL.md`)

```markdown
## <kebab-case-name> (<methodology|pitfall|decision>)

<the same content as above, without its own frontmatter — the section
inherits the frontmatter of the file that contains it.>
```

## Hard rules

- It does not implement product code nor fix the task files it describes: it
  only distills knowledge about what already happened.
- The read subagents (LOGS, PLAN, INVENTORY) never synthesize: they return
  findings with anchored evidence, the classification is done by `review`.
- One single concern per entry: never mix types (`methodology`, `pitfall`,
  `decision`) in the same block.
- Parallel builders only in `vault/` mode; sequential in single-skill mode.
- It does not delegate to `forja`: it does not exist yet.
