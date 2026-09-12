# gubia / run

Action `/gubia run`: launch the gubia loop against the plan file (default
`plan/plan.md`, max 500 iterations) in the background and **watch it without
intervening**. Only switches from "watch silently" to "diagnose and propose"
when the stop file (`stop.md` next to the plan) appears or the process dies.

Four phases, with maximum delegation to ephemeral read-only subagents: the
main agent only launches the process and relays 1-2 line summaries, so as
not to clutter its context with bulky logs or plans.

## Phase 1 — Preflight (reader subagent)

Delegate to a read-only subagent that validates, in order, and aborts if
anything fails:

1. The plan exists and there is no stop file next to it yet.
2. Every `- [ ]` entry in the plan links to an existing task file.
3. There is at least one `[ ]` subtask in some linked task file.
4. Progress baseline: count of `[ ]`/`[x]` before launching.
5. The engine is available and the configuration is valid (`gubia config
   validate`, which includes checking that the `gubia` and `judge` skills
   are installed in the harness of each model in the active fallback list).
6. There is not already another loop running against the same plan — check
   by process, not just trusting the engine's flock.

The subagent returns ok/abort + baseline + resolved command. If it aborts,
the reason is relayed and phase 2 is not started.

## Phase 2 — Launch (main agent, not a subagent)

The only step the main agent itself executes: the background process must
hang off this session, not off an ephemeral subagent that terminates.

- Launch `gubia run <path-to-plan> [max_iterations]` with `setsid` (or an
  inline `perl` fallback if `setsid` is not available).
- Launch **with the cwd explicitly set to the workspace root**: the engine
  takes the root from the `pwd` of the launch, and an agent session's cwd
  is not guaranteed.
- Capture the PID in `.gubia/<slug>.pid`.

## Phase 3 — Watching (delegated polls, cadence ≥ 15 min)

Each poll delegates to a reader subagent that:

- Detects the appearance of the stop file.
- Reads the most recent log.
- Recounts `[ ]`/`[x]` against the baseline.
- Checks the stall signal (see below).
- Returns a 1-2 line summary.

The main agent keeps only that summary, never the full log.

**Stall detection**: with no per-iteration timeout, a hung agent blocks the
loop indefinitely. The log's mtime alone can't distinguish "hung" from
"thinking" (with `hide_agent_reasoning=true` and `thinking=false`, an agent
reasoning at length writes nothing). That's why the signal is **broad**,
with three independent components:

1. mtime of the active iteration's log.
2. mtime of any file under the repo root.
3. CPU activity of the agent's process group.

**Three consecutive polls with none of the three signals** (~45 min) are
reported as a stall. In v1 this is **a report, not an action**: the human
decides whether to intervene. Automatic kill is out of scope for this
version.

## Phase 4 — Diagnosis (subagent)

On detecting the stop file or the process ending, delegate to a subagent
that classifies the reason:

- **Plan complete**: zero pending subtasks.
- **Judge stuck**: subtasks remain pending and the stop file comes from the
  `judge` skill.
- **Other**: max iterations reached, `fallback-exhausted`, crash.

The subagent returns a diagnosis + a single proposed next step. The main
agent relays the result and cleans up the PID file, **without executing
the proposal**.

## Hard rules

- **Non-intervention**: this action's only writes are launching the process
  and recording the PID. It never edits the plan/tasks, never checks off
  boxes, never invokes other skills, never touches `.gubia/state.env`.
- **The stop file is never deleted** without an explicit request from the
  user at that moment: it may be a deliberate stop (human checkpoint), not
  a stale leftover.
- **Kill scoped by PID only, never by name**: if the process must be
  killed, only via the saved PID and its group (`kill -TERM -<PGID>`).
  `pkill`/`killall` by name or pattern is forbidden.
- **One loop per plan**: never launch a second loop against the same plan;
  verify by process before launching, don't blindly trust the flock.
- **Poll cadence ≥ 15 min**, unless explicitly requested otherwise.
