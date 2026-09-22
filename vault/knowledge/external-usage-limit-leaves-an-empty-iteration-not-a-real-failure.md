---
name: external-usage-limit-leaves-an-empty-iteration-not-a-real-failure
description: an empty .out from a gubia iteration alongside a .err with a usage-limit error from the underlying LLM provider is not a regression of the work; the engine resumes on its own in the next iteration
type: pitfall
---

# External usage limit leaves an empty iteration, not a real failure

If the `.out` of a gubia engine iteration comes out empty (no
`SUBTAREA_COMPLETADA=true` and no subtask marked) and the corresponding
`.err` contains an exhausted-usage-limit message from an LLM provider
(e.g. "You've hit your usage limit... try again at..."), do not interpret
this as a failure of the work itself or of the task file: it is an
external quota exhaustion, outside the execution.

Evidence: during the migration to `vault/` (task `plan/task/04.md`), the
iteration `.gubia/logs/14.out` came out empty while `14.err` showed that
Codex quota error. The next relevant iteration (`.gubia/logs/15.out`)
resumed the first pending `[ ]` subtask without any problem, with no
`[regression fix]` mark and no manual intervention.

Do not create a repair subtask or a regression checkpoint for this
symptom: it is enough to let the next loop iteration resume the subtask
from where it left off.
