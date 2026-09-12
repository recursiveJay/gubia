# judge / unblock

Action that diagnoses why a block keeps accumulating rejections and, if
the criterion as stated is unreachable, documents the problem and inserts
the fix subtask before the stuck `[judge]`. Does not implement the fix.

## When it triggers

When there is a pending `[judge unblock]` subtask, inserted by `judge.md`
on the 5th consecutive rejection of a block. It is the highest-priority
action among the automatic ones.

## Key rules

- Binary diagnosis: is the criterion reachable as stated? When in doubt,
  it's treated as reachable (Action B).
- **Unreachable (Action A)**: writes a diagnosis anchored in concrete
  evidence, inserts the fix subtask before the stuck `[judge]` and, if
  needed, corrects the `[judge]`'s own criterion/evidence (the only
  exception to not touching existing `[judge]`s).
- **Reachable (Action B)**: writes no diagnosis at all; only unmarks the
  implementation subtasks, keeping the rejection history, and lets the
  ordinary cycle continue.
- Logs from `.gubia/logs/` are read via subagents that return only the
  distilled conclusion, never loaded in full.
- Never creates `stop.md` (that's exclusive to Case C and the 10th
  rejection, handled by `judge.md`); only edits the block's task file.
- One unblock per block.
