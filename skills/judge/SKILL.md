---
name: judge
description: "Independent reviewer of the plan's task files: judges evidence after checked subtasks, unblocks the loop on accumulated rejections, and plans [judge] checkpoints."
---

# judge

Thin router for the `judge` skill. It contains no action logic: each action
lives in its own file, loaded only when needed. No action implements product
code: gaps are reflected as feedback, checkpoints, or diagnostics, never as a
direct fix.

## Triggers

- There is a pending `[judge unblock]` subtask `[ ]` → load `unblock.md`.
- There are `[x]` implementation subtasks with a pending `[judge]` (or
  `[judge regression]`) after them → load `judge.md`.
- There are no pending `[x]` to judge and the plan needs validating
  (creation or review) → load `instrument.md`.

## Priority among automatic actions

`unblock` > `judge` > `instrument`. Unblocking takes precedence because it is
inserted right before a `[judge]` with accumulated rejections: the blockage
must be diagnosed before judging can continue.

## Where the task file comes from

It's the one linked from the plan entry; no action in this skill derives its
path or assumes a specific directory.

## Prior context

Before acting, read `AGENTS.md` and, if present, `CLAUDE.md` at the root of
the current workspace, and follow them for commands, environment, evidence,
and style. It does not walk up parent directories or scan outside the
workspace to find them.

## Hard rules

- Does not implement product code in any of its three actions.
- In normal use only the corresponding action file is loaded; the others are
  only read when reviewing or maintaining the skill itself.
