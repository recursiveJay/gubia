# Engine (`gubia`)

Spec of the live loop engine, written against the current `gubia` code
(2172 lines, bash monolith). Supersedes the historical v1 spec, which
described a ~550-line engine with layers and capabilities that were never
implemented; here every fact is anchored to the live file.

## What it is

`gubia` is a loop engine that drains markdown task plans: it locates the
next pending subtask, injects a fixed contract + the plan's content into a
CLI agent, captures its exit code, and rotates model on failure. The name
is the woodcarver's gouge: from a rough goal it carves an executable plan.
From it come the `gubia` executable, the global config
`~/.config/gubia/agents.sh`, the environment prefix `GUBIA_ROOT`/`GUBIA_PLAN`,
and the `.gubia/` state directory in the repo.

The engine is native bash, not Go: implemented from scratch, with no
binary or `inspect` subcommands inherited from the original.

## Command-line interface

The interface is **mixed**, not purely positional (`gubia:2105` `main`):

- `gubia run <plan-path> [max-iterations]` — the loop. `gubia <plan-path>`
  is an alias (only if the first argument is an existing file). Default of
  `max-iterations`: 500. The cap is local to the invocation: it isn't
  persisted, and a relaunch after a normal stop gets its N iterations back
  (`gubia:1526` `run_resolve_max_iterations`).
- `gubia effort set <low|medium|high>` — invoked by the agent from an
  `[effort …]` subtask. Writes two keys (see "Local state").
- `gubia config validate` — preflight: validates catalog, scalars and
  skills.
- `gubia -h|--help|help` (and `gubia run -h|--help`) — prints usage to
  stdout and exits 0, **before** creating `state.env` or launching
  anything (`gubia:2105`).

`main` guarantees state before dispatching: `state_ensure` + `state_read`
+ `state_validate` run for every subcommand except help, so a corrupt
`state.env` aborts `effort set` just as much as the loop.

**Only `run` acquires the `flock`** on the plan. `effort set` runs from
inside an iteration, with the engine blocked waiting on the agent: taking
the plan's lock would self-deadlock the loop. `config validate` doesn't
take it, so it can validate while a loop is running.

## Contract injected per iteration

The engine prepends a **fixed header** to the plan's content on each
iteration (`gubia:508` `run_contract_header`, `gubia:568` `run_prompt`).
Composition: header + `cat <plan>`. Nothing else — no truncation, no
concatenating task files. The agent navigates the on-disk plan on its own.

The header is **literally fixed**: a heredoc with a quoted delimiter
(`<<'EOF'`) that bash doesn't expand, so `${GUBIA_PLAN}`/`${GUBIA_ROOT}`
come out as raw text. The only variable part — where the root is and where
the plan is — travels through the **child process's environment**
(`GUBIA_ROOT`, `GUBIA_PLAN`; `gubia:425` `run_export_env`), never
interpolated into the text. That way no absolute path enters what the
agent reads or could copy into a versioned file.

The header fixes the loop's five rules: (1) locate the plan's first
`- [ ]` and follow its link to the task file, creating `stop.md` next to
the plan if none remain; (2) execute a single subtask per iteration, with
the bounded exception of work already done (max 3 skips with nameable
evidence); (3) propagate `[x]` upward when a task file completes; (4)
emit `SUBTASK_COMPLETED=true` only if the active subtask was completed;
(5) stop. A `[judge]` is never skippable and requires the `judge` skill
installed.

The engine **doesn't check off boxes** in v1: write authority over the
plan and task files rests with the agent. The engine locates the active
task and captures the result, but doesn't write to the plan.

### What the engine does NOT do, in parallel

The historical spec described an integrity detector: a snapshot before
and after the active task file (state of each checkbox + sha1 of the
normalized prefix), a check that `[ ]`→`[x]` transitions form a contiguous
prefix, and a warning on stderr. **That capability is absent from the
live code**: there's no `integrity_` layer, no snapshot, no transition
check, no `sha1` computation. The loop trusts the
`SUBTASK_COMPLETED=true` token and the judge to catch improper skips.
The detector (in warning mode) and abort/revert are left for v1.1/v2 (see
"Milestones").

The engine **doesn't write**
`.gubia/<slug>.pid` (unlike what the historical spec claimed): the `run`
process's PID isn't published to disk.

## Local state (`state.env`)

`.gubia/state.env` is a plain file in the repo with 6 scalars, re-read at
the start of each iteration (`gubia:706` `run_reload_state`). The engine
creates it on the first iteration with defaults (`gubia:74` `state_ensure`):

| Key | Default | Domain |
|---|---|---|
| `effort_level` | `medium` | `low\|medium\|high` |
| `fallback_list` | `default` | `default` (only set in v1) |
| `model_index` | `0` | integer ≥ 0 |
| `thinking` | `true` | `true\|false` |
| `memory_max` | `8G` | integer + suffix `K\|M\|G\|T`, `%`, or `infinity` |
| `loop_max_logs` | `20` | integer ≥ 1 |

**Never sourced**: the agent writes it (via `gubia effort set`), so
`source` would be arbitrary code execution. It's read line by line with an
allowlist of the 6 keys (`gubia:136` `state_read`): anything outside the
set is silently discarded; assignment is literal via `printf -v` (no
`eval`) + explicit `export`. A complete pair of quotes (single or double)
is stripped on read, because the original `state.toml` used quotes and a
dragged-along one would produce an invalid value with a confusing
message.

**Abortive validation, never auto-repair** (`gubia:188` `state_validate`):
a missing key or out-of-range value → exit 2 naming the key and value.
Auto-repairing to the default hides the failure and leaves the loop
running with a different effort than what the plan requested. The guard
on `model_index` against the active list's length
(`gubia:224` `state_guard_model_index`) is the sole exception: it resets
to `0` with a stderr warning, without aborting, because `state.env` can be
left with a stale index if the engine dies between `effort set`'s two
writes.

**Surgical write with `sed -i`** (`gubia:255` `state_set`): `grep -q` for
existence + `sed -i` on the line, never regenerating the whole file. There
are two writers (the agent via `effort set`, the engine when rotating) and
`sed` touches its line and only its line, immune by construction to
clobbering what the other wrote. A key missing from an already-created
file is a corrupt file → exit 2.

### Consistency when changing effort level

`model_index` is an index **within the active level's fallback list**, and
the lists have different lengths. `gubia effort set` (`gubia:327`) writes
**two keys** in the same invocation: `effort_level` to the requested level
and `model_index` reset to `0`. The agent only asks for the level; the
engine guarantees consistency.

The streak sentinel lives in the `run` process's memory, not on disk, so
after a level change `state_read` clears it upon detecting that
`effort_level` changed relative to the previous re-read (`gubia:163`).

### Boundary between global config and local state

- `agents.sh` (resolved in order: the repo's `config/agents.sh`, falling
  back to `~/.config/gubia/agents.sh`; `gubia:47`): global config, touched
  by the human and the engine, never by an iteration's agent. It's bash on
  purpose (functions, arrays) and **is** sourced.
- `.gubia/state.env`: mutable local state, 6 keys, written by the agent
  and the engine. The only poisonable file → allowlist.

## Model rotation

**Circular within the effort level** (`gubia:289`
`state_rotate_model_index`): exit ≠ 0 → `model_index++`; past the last
one, back to `0`. The decision is made by `run_decide_rotation`
(`gubia:999`):

- rc 0: the iteration went well. The streak closes (`run_streak_reset`)
  and **no rotation happens**: the model that just worked is the one to
  keep using.
- rc ≠ 0: the sentinel is marked with the index that failed **before**
  rotating (`run_streak_mark`), rotation happens, and it's checked whether
  the rotation came back to the saved index (`run_streak_check`).

**Streak sentinel** (`gubia:736`): the `model_index` of the first failure
is saved; if it's reached again without any successful iteration in
between, it aborts with `fallback-exhausted` (exit 3). Any successful
iteration resets the sentinel, so a long run can cycle through indefinitely
— the real regeneration happens between successes. The sentinel is memory
of the `run` process: an engine that restarts begins with no streak.

**The engine doesn't automatically escalate effort level** in v1:
promoting to `high` on a deterministic failure burns money with no model
about to solve it. Automatic promotion is left for v2, tied to the
exhaustion detector. **Deliberate** escalation (the judge escalates after
three rejections) isn't the same thing: there, the judge decides, not the
engine.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Normal exit: stop file present or iteration cap exhausted |
| 1 | `flock` contention: another loop is already running on the plan |
| 2 | Invalid configuration or usage (corrupt `state.env`, broken catalog, non-executable CLI, malformed arguments) |
| 3 | `fallback-exhausted`: rotation came back to the first failure with no success in between |
| 130 | Interrupted by SIGINT |

rc 126/127 (non-executable / not-found CLI) are an immediate `die` with
exit 2, **never rotating** (`gubia:1247` `invoke_rc_die`): rotating would
burn the whole list in seconds repeating the same installation error.
Signal interruption is checked **before** interpreting the rc
(`gubia:923` `run_invoke_iteration`): a SIGINT produces rc=130 from
`wait`, and without that check the engine would rotate model over a
user's Ctrl-C.

## Process management

`setsid` + closed stdin (or prompt file) + stdout/stderr to separate files
under `.gubia/logs/<iter>.{prompt,out,err}` (`gubia:1411` `invoke_agent`).
On finishing (or aborting), the **process group** is killed, not the
process (`gubia:1211` `invoke_kill_group`): the agent's CLI spawns
subprocesses (MCP servers, `git`) that outlive the parent and would keep
writing to the plan files during the next iteration. Shutdown is
`kill -TERM -<PGID>`, a short wait (5 s polling `kill -0`), `kill -KILL
-<PGID>` only if the group is still alive. With `setsid` and no
intermediate process, PID == PGID of the child.

**Memory limit** (`gubia:1101` `invoke_prepare`): with `systemd-run`
detected by `require_tools` (`gubia:1037`) and a configured `memory_max`,
the invocation is wrapped with `systemd-run --user --scope -q -p
MemoryMax=<value>`. The `-q` silences systemd-run's banner so it doesn't
pollute the agent's `.err`. The order is `setsid systemd-run … --
<agent>`: `--scope` runs the command in its own process, so the saved PID
is still the group's PGID. If `systemd-run` isn't present, a one-time
stderr warning and it runs unbounded. **Never `ulimit -v`**: `RLIMIT_AS`
is virtual address space, not RSS; engines like DuckDB/Arrow reserve
addresses without touching them and die with SIGSEGV instead of OOM, and
that SIGSEGV would arrive as exit ≠ 0 and rotate model over a badly-set
limit.

**Traps** (`gubia:1302` `invoke_trap_int`, `gubia:1355` `invoke_trap_exit`):
the SIGINT trap re-raises the signal (`trap - INT; kill -INT "$$"`)
instead of `exit 130`, so the parent can distinguish "killed by
interruption". The EXIT trap captures `$?` on its first line, closes the
group if one is still alive, and re-emits the code with `exit "$rc"`.
Both carry a re-entry guard. **The lockfile is never deleted in the
trap**: that's the classic race (B opens, A deletes, C creates another, B
and C lock different inodes); fd 9 opened by `run_acquire_lock` only
releases the `flock` when the process dies.

**No per-iteration timeout** in v1: interrupting by the clock an agent
that's thinking does more harm than waiting for it. Automatic killing of
a stalled iteration is v1.1 (not implemented). Accepted consequence: a
hung agent blocks the loop with the `flock` held until a human steps in.

### Concurrency

`flock` per plan (`gubia:614` `run_acquire_lock`): `exec 9>".gubia/<slug>.lock";
flock -n 9 || exit 1`, where `<slug>` is the plan's path relative to the
root with `/`→`-` (`plan/plan.md` → `plan-plan.md`). The lock is **per
plan**, not per repo. No lock on `state.env`: it's per-repo state, writes
aren't concurrent (the agent only writes between iterations, with the
engine blocked waiting on it).

### Engine files in the repo

| Path | What it is | Scope |
|---|---|---|
| `.gubia/state.env` | mutable local state (6 keys) | per repo |
| `.gubia/logs/` | prompt, stdout and stderr per iteration (`<iter>.{prompt,out,err,console}`) | per repo |
| `.gubia/<slug>.lock` | `flock` lockfile | per plan |

### Log rotation (`loop_max_logs`)

After each iteration's files are written, the engine prunes
`.gubia/logs/` to the `loop_max_logs` most-recent iteration log sets
(`gubia:1563` `run_prune_logs`, called post-write in the loop at
`gubia:1739` `run_prune_logs || true`). The retention unit is the
**iteration set** — every file sharing one numeric `<iter>` prefix across
the `.prompt`, `.out`, `.err`, and `.console` suffixes — and it is treated
atomically: every suffix of a pruned set is deleted, never a subset (R1).
Ordering is by **modification time** of each set's `.prompt` anchor, not
by numeric prefix, because `<iter>` restarts at `1` on every relaunch and
collides across runs (R2); `.prompt` is written unconditionally every
iteration (`invoke_prepare`), so it is the reliable mtime anchor. Only the
four known suffixes are ever touched; unrelated files (`.gitkeep`, future
engine files) are left alone (R5).

Pruning is **non-abortive** (R6): it is maintenance, never an iteration
result. Every failure path is guarded (`|| continue`, `|| return 0`,
`rm -f … || true`), and the call site adds `|| true`, so a failing `rm` or
an unreadable directory can neither abort the loop nor feed the
model-rotation streak. Pruning runs after the write so that
`loop_max_logs=1` keeps exactly the current set (R4).

## Script structure

Monolith of **2172 lines** in a single executable, with `main` under a
`[[ "${BASH_SOURCE[0]}" == "$0" ]]` guard (`gubia:2170`) so tests can
source it without executing it. Mandatory header: `set -euo pipefail`,
`shopt -s inherit_errexit`, `export LC_ALL=C`, `umask 077` (logs carry
prompts and sometimes credentials in traces), and a bash version guard
≥ 4.4 before the options (`gubia:12`).

**Real layers by prefix**: `state_`, `run_`, `invoke_`, `config_`, plus
`require_tools` and the `cmd_*`/`main` dispatchers. The historical spec
also named `agents_` and `integrity_` as layers of the module system —
**they don't exist in the live code** (the script's own header comment
names them out of inertia, but no function carries those prefixes). If it
ever gets split, the cut is by layer — by shared data, not by size.

### Engine capabilities

- **Locate the active task file** (`gubia:459`
  `run_locate_active_task`): `grep -m1` for the plan's first `- [ ]`,
  extraction of the markdown link's path `](…)` (plain form or angle
  brackets `](<…>)`), resolved **relative to the plan's directory**. Exit
  1 if none remain pending (not an error); exit 2 if the first `- [ ]`
  carries no link (malformed plan). That's the entirety of v1's
  "parsing".
- **Validate configuration** (`gubia:2070` `cmd_config_validate`):
  sources `agents.sh` and checks with `declare -F` the four agent
  functions (`agent_codex`, `agent_claude`, `agent_omp`, `agent_devin`);
  the 6 `state.env` scalars present and in domain; and the `gubia` and
  `judge` skills installed in each model's harness on the active fallback
  list (`gubia:1989` `config_validate_skills`). `agent_probe` isn't
  required: it's the catalog's test agent, not a CLI. It accumulates all
  failures and reports in one pass; exit 2 if anything fails.
- **Write `state.env`**: `gubia effort set` sets `effort_level` and
  resets `model_index` to `0` from an `[effort …]` subtask.

### Plan resolution and path anchors

`run_resolve_plan` (`gubia:383`) captures the root as `pwd -P` once at
startup and resolves the plan to absolute via `cd` + `pwd -P` (never
string concatenation: a `plan/../../outside.md` would escape the root on
the filesystem). If the plan doesn't fall under the root, exit 2.
`run_export_env` exports `GUBIA_ROOT` (absolute) and `GUBIA_PLAN`
(relative to the root) to the child's environment.

## Milestones

The distinction matters because lumping everything into "v2" means
nothing gets done until the full graph is ready.

- **v1.1 — harden with what running v1 teaches, no new parser**:
  (1) the integrity detector goes from non-existent to warning and then
  to abort/revert, once calibrated with real data; (2) automatic killing
  of a stalled iteration, detected by `gubia run`'s watchdog; (3) the
  engine publishes the active agent's PGID to `.gubia/<slug>.agent.pid`
  and deletes it on finishing —a prerequisite for the previous item,
  because today killing the engine's PID would kill the whole loop
  instead of just the hung iteration.
- **v2 — what the graph-based parser requires**: prompt truncation,
  `Active task:`, an actionable token (`SUBTASK_COMPLETED=true` goes
  from telemetry to actionable), check-off authority in the engine's
  hands (the engine marks `[x]` when the agent returns the token),
  `switch_on_exhaustion` with its exhaustion detector, and the
  `{selector}` rune if it comes back with semantics. With authority in
  the engine, v1's three patches disappear —the already-done exception,
  delegated propagation, and the transition detector— because the agent
  no longer has anything to mark.

## Reusable patterns

- **Contract in the engine, not the artifact**: the plan's format stays
  decoupled from the engine's version. Updating the engine doesn't leave
  old plans running under old rules.
- **Literal termination token as success signal**:
  `SUBTASK_COMPLETED=true`, parseable with a `grep`, with the burden of
  proof on the agent.
- **Exception with mandatory evidence**: allow a shortcut only if whoever
  takes it puts the justifying proof in writing.
- **Abortive validation without auto-repair**: an out-of-range value
  aborts naming the problem instead of hiding it under a default.
- **Detect in one version, react in the next**: deploy the detector in
  warning mode to calibrate it before giving it abort power.
- **Write authority as a versioning axis**: the same machine with the
  permission to check off in the agent's hands (simple, tolerant) or the
  engine's (strict, verifiable).
