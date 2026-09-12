# gubia / run

Action `/gubia run`: launches the gubia loop against the plan in the
background (max 500 iterations) and watches it without intervening,
delegating almost everything to ephemeral read-only subagents so as not
to clutter the main agent's context with logs or the full plan.

Four phases: preflight (validates plan, links, pending subtasks,
baseline, engine configuration, absence of another running loop),
launch (the main agent itself launches the process with `setsid` and an
explicit cwd at the root, saves the PID), monitoring (≥15 min polls that
count progress and detect stalls via three independent signals: log
mtime, mtime of any file in the repo, CPU activity) and final diagnosis
when the stop file appears or the process dies (end of plan / judge
deadlock / other).

## Key rules

- Non-intervention: this action's only write is launching the process
  and noting the PID; it never edits the plan/tasks or invokes other
  skills.
- The stop file is never deleted without an explicit user request.
- Stops only by saved PID/PGID, never by name (`pkill`/`killall`
  forbidden).
- Only one loop per plan; verified by process, not just by the engine's
  flock.
- Stall (~3 polls with no signal, ~45 min) is a report, not an action:
  automatic kill is out of scope for v1.
