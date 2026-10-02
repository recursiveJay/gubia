# gubia / effort

The per-file `[effort …]` placement, drained by the loop. This file is
loaded when the engine reaches a manifest bullet of the form
`- [ ] Interleave effort subtasks for \`task/NN.md\`` (queued by
`effort-expand-00.sh` right after the Effort subtask of `task/00.md`). It
places the standalone `[effort low|medium|high]` subtasks into that one
product task file, deterministically: the transitions come from the script,
the model never invents them.

## The only thing this bullet does

For the target file named in the bullet (`task/NN.md`):

1. Run `skills/gubia/scripts/effort-plan.sh task/NN.md --apply`.
2. Review the `# unmatched` section the script printed (if any): bullets
   whose text matched no keyword and therefore inherited the previous
   level. Confirm that inheritance is right; the script has already applied
   it, so this is a read-back, not a re-edit — only a wrong assignment
   warrants hand-correction, which is out of the normal path.
3. Mark the `Interleave effort subtasks …` bullet `[x]`.

It does nothing else: it doesn't touch other task files, doesn't edit the
script, doesn't move or reword the `[effort …]` bullets the script
inserted.

## Abort (exit 3)

`effort-plan.sh --apply` aborts with exit 3 without touching the file if any
content bullet is already `[x]`. That is the phase-0 precondition: the
engine must not have started draining the file yet. On that abort, do not
hand-insert bullets and do not mark the manifest bullet `[x]` — report the
stale state; the effort placement for this file was meant to run before any
of its content was drained, and the file needs re-planning, not patching.

## Contract

- The transitions are the script's output, not the model's judgment. The
  model only reviews the `# unmatched` bullets; it never adds, drops, or
  reorders a transition.
- One file per iteration, serially, no subagents and no parallelism: each
  file's placement is a single clean iteration.
- `task/00.md` stays excluded from effort marks, as today.
