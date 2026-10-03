# TODO — improvements

Index of pending improvements. Open a file in `todo/` only when its row is
relevant to the task at hand; link this index, not the files.

- **Add:** create `todo/<problem-slug>.md` (frontmatter `area`, `kind`;
  sections Problem, an optional middle section named to fit (Observed
  symptom, Root cause, Motivation…), Done when, optional Refs) and add a
  row here.
- **Land:** delete the file and its row.

| File | What it describes | Area |
|---|---|---|
| [scribe-incidental-knowledge.md](todo/scribe-incidental-knowledge.md) | `scribe` writes one session's incidental repo state into the vault as durable knowledge; needs a reusable-vs-incidental filter | scribe |
| [loop-rule-2-no-enforcement.md](todo/loop-rule-2-no-enforcement.md) | Contract rule 2 (one subtask per iteration) is unenforced; an agent did a later subtask's edit ahead of turn and a skip hid it | engine |
| [parallelize-phase-0.md](todo/parallelize-phase-0.md) | Phase 0 runs per-file work in series; design a parallel version that keeps one action per iteration | phase 0 |
