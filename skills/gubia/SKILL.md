---
name: gubia
description: "Manages the work plan of a gubia loop over a repository: drafting the plan (init, optional), materializing it (phase0), and launching/monitoring the engine (run)."
---

# gubia

Thin router for the `gubia` skill. It contains no action logic: each action
lives in its own file, loaded only when needed.

## Triggers

- `/gubia init` (or equivalent phrases) → loads `init.md`. Optional, prior to
  phase0, for when a human isn't sure how to draft the plan's objective; only
  on explicit invocation, never by proactive detection.
- `/gubia phase0` (or equivalent phrases) → loads `phase0.md`.
- `/gubia run` (or equivalent phrases) → loads `run.md`.
- **Proactive detection**: when inspecting a repo with `plan/plan.md` that
  contains no `- [ ]`/`- [x]` line, suggest `/gubia phase0` (do not launch it
  on your own).

## Default plan location

`plan/plan.md`. Where its task files live is not decided by this skill: it's
set by whoever creates them (`phase0.md`, under `task/` next to the plan) and
communicated by the link in each plan entry.

## Loop contract

The contract for each iteration (active task, termination token, prohibition
on editing checkboxes) is injected by the engine, not by this skill or the
plan. A `## Loop instructions (ralph)` header inherited in the plan is inert
text.

## Hard rules

- Do not walk parent directories or scan outside the workspace looking for
  `AGENTS.md`/`CLAUDE.md`: read them only at the root of the current
  workspace.
- Do not launch `phase0` on your own initiative: only suggest it.
- Do not suggest or launch `init` on your own initiative: only on explicit
  user invocation.
