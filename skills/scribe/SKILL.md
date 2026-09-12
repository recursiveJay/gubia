---
name: scribe
description: "Distills the accumulated learning of a completed task into reusable knowledge (vault/conocimiento/ or a single skill), and prunes that knowledge when it grows too large [scribe]."
---

# scribe

Thin router for the `scribe` skill. It does not contain the action logic: each
one lives in its own file, loaded only when needed. The name is deliberately
left in English: "escriba" in Spanish is confused with forms of the verb
"escribir" ("¡escriba esto!"), which can mislead an LLM reading the
`[scribe]` marker out of context.

## Triggers

- There is a pending `[ ]` `[scribe]` subtask that is the last one in the task
  file, with everything before it (including all `[judge]`/`[judge regression]`)
  marked `[x]` → load `review.md`. `review.md` decides on its own whether to
  also chain `consolidate.md` in the same pass (see "Chaining" in
  `review.md`).
- Explicit manual invocation `/scribe review` or `/scribe consolidate` (or
  equivalent phrases) → load the named action's file
  directly, without waiting for the marker in the task file.
- **No proactive detection beyond the `[scribe]` marker**: it is not suggested
  nor launched on its own initiative outside the two cases above.

## Where the task file comes from

It is the one linked by the plan entry; no action of this skill derives its
path or assumes a specific directory (same contract as `judge`).

## Knowledge destination

No action of this skill assumes where the project's knowledge lives:
`review.md` decides it in its Step 0, repeating the check on every
invocation (`test -d vault/` → `vault/conocimiento/`; otherwise the single
skill `skills/<repo-root-directory-name>/SKILL.md`, creating it if it does
not exist).

## Prior context

Before acting, read `AGENTS.md` and, if present, `CLAUDE.md` at the root of
the current workspace, and respect them for commands, environment, evidence,
and style. It does not walk parent directories nor scan outside the workspace
to find them.

## Hard rules

- It does not implement product code in either of its two actions: it distills
  and organizes knowledge, never fixes the code or the task files it
  describes.
- It does not delegate to `forja`: that skill does not exist yet in this
  project: all references to it are omitted until it is created in another
  session.
- In normal use only the corresponding action's file is loaded; the
  other one is only read when reviewing or maintaining the skill itself.
