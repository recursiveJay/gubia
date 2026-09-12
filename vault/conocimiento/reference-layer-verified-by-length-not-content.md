---
name: reference-layer-verified-by-length-not-content
description: when creating a reference layer (summaries, not a copy) over source files, the [judge]'s acceptance criterion compares length/size against the source, not just an eyeballed content review
type: methodology
---

# Reference layer verified by length, not content

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
