---
name: agent-invocation-and-catalog-in-gubia
description: "How gubia defines, invokes, selects, decouples, and tests the agent catalog (config/agents.sh, invoke_prepare, run_resolve_agent, state_); consult before touching any piece of this subsystem."
type: decision
---

# Agent invocation and catalog in gubia

Five design decisions of the same subsystem — the agent catalog and
invocation in `gubia` — consolidated here because they reference each other
and touching them separately means touching the same mechanism from
different angles.

## Output contract of `config/agents.sh`: global variables, never a subshell

The four functions `agent_codex`, `agent_claude`, `agent_omp`, and
`agent_devin` in `config/agents.sh` do not return their result with
`return`/`echo`: they fill the variables `GUBIA_ARGV`, `GUBIA_ENV`,
`GUBIA_PROMPT_MODE`, and `GUBIA_OUTPUT_MODE` **in the caller's scope**
(without `local`), documented in the contract block at the top of
`config/agents.sh`. It is the only way to return a bash array from a
function without going through a subshell.

Consequence for anyone consuming these functions: **never call them inside
`$(...)` or any other subshell** — the write to the output variables would
be lost. Invoke them in the same shell and read
`GUBIA_ARGV`/`GUBIA_ENV`/`GUBIA_PROMPT_MODE`/`GUBIA_OUTPUT_MODE` right
after.

## Dispatch by real arity, without a common signature

`invoke_prepare` (`gubia:1086-1134`) dispatches each real agent by function
NAME with its literal arity, without unifying signatures: `agent_codex
<model> <effort> <thinking> <console_output>` (4), `agent_claude <model>
<effort> <thinking>` (3), `agent_omp <model> <effort> <thinking>
<prompt_file>` (4), `agent_devin <model> <prompt_file>` (2). The `*)` of
the `case` keeps the historical three-argument signature for `agent_probe`
and the local test agents (`agent_fake`): only the four real CLIs have
distinct arity contracts. Adding an agent to the catalog = adding a `case`
with its real arity, never inventing a common interface.

The per-file prompt (`GUBIA_PROMPT_MODE=file`) already lives in
`.gubia/logs/<log_seq>.prompt` (`gubia:1116`; `<log_seq>` is the
monotonic sequence number, not the per-run `iter`); it is passed to the agent's function as a
positional argument, and it is the function itself that wires it into
`GUBIA_ARGV` with its flag (`-p "@$prompt_file"` in omp, `--prompt-file`
in devin). The prompt is not appended to the end of `GUBIA_ARGV`
generically: that append served the probe and no longer applies to agents
that wire their own flag.

The output of an agent with `GUBIA_OUTPUT_MODE=file` (codex) is the
`console_output` file that the function itself received as an argument, not
the process's stdout. `invoke_agent` normalizes it to `.out` after the
`wait` (`gubia:1456-1465`): it copies `console_output` to
`invoke_stdout_path`, so the rotation consumer reads a single uniform
observation without branching by origin. If the agent dies before
materializing the file, `.out` stays empty and the agent's real rc is
preserved — not an artificial `cat` failure. `console_output` (destination
of the CLI output) is distinct from `invoke_stdout_path` (capture of the
process's stdout).

Consequence for tests: a stub that impersonates a REAL agent (`agent_omp`,
`agent_codex`...) must accept the arity the engine passes to that name
(4/3/4/2), or the dispatch hands it too many or too few arguments. For the
generic three-argument signature use `agent_fake` or `agent_probe`, which
fall into the `*)` of the `case`.

Evidence: `gubia:1086-1134` (dispatch by arity), `gubia:1456-1465`
(`console_output`→`.out` normalization), `config/agents.sh:160-184` and
`:191-210` (omp/devin wire their `prompt_file`),
`tests/invoke_prepare_real_agents.bats` (arity per agent and capture from
`console_output`), `tests/invoke_agent_launch.bats` (stubs `agent_omp` at 4
args, `agent_fake` at 3).

## Selection of the active agent: `run_resolve_agent` translates `model_index`

The circular rotation of `model_index` (`state_rotate_model_index`) only
moves the index; the **selection** of the agent that runs each iteration is
materialized by `run_resolve_agent` (`gubia:835-862`): given `effort_level`
and `model_index`, it reads the entry `GUBIA_FALLBACK_<level>[$index]`,
resolves it against `GUBIA_MODELS`, and returns the pair
`(agent_<name>, model)` in `run_resolved_agent_fn`/`run_resolved_model`.
`run_invoke_iteration` calls it before `invoke_agent` (`gubia:908-918`), so
the index the rotation left points to the real CLI that runs the next
round.

`agent_probe` is NO longer the loop's default agent: it remains as the
catalog's test agent, reachable by tests and configuration, never selected
by `run_resolve_agent` (which only resolves the four real functions).

Broken catalog = `die` with exit 2 (no rotation): a key of the active list
with no entry in `GUBIA_MODELS`, or an agent without an `agent_*` function,
aborts in `run_resolve_agent` before building any invocation. The
non-aborting range guard (`model_index` >= length → 0) remains `state_`'s,
not this one's: a badly indexed list is repaired; a catalog without the
function or the model is a configuration failure that makes no sense to
rotate.

Evidence: `gubia:835-862` (`run_resolve_agent`), `gubia:908-918`
(`run_invoke_iteration`), `tests/run_resolve_agent.bats` (valid input →
function+model; broken catalog → exit 2),
`tests/gubia_run_resolves_real_agent.bats` (one iteration invokes the real
agent by `model_index`, not `agent_probe`).

## `state_` deliberately decoupled from the catalog

The `state_` module of `gubia` (management functions for
`.gubia/state.env`) was deliberately designed decoupled from the agent
catalog (`config/agents.sh`): `state_guard_model_index` receives the length
of the active fallback list **by argument**, it does not resolve it
internally by consulting the catalog. The reason, noted in
`tests/state_model_index.bats`, is that `state_` must not `source` global
configuration in order to remain an independent module testable in
isolation. Verified after implementing `agents.sh`: it contains no `source`
nor cross-reference to the `state_` module, so the decoupling stays intact.

Future tasks that integrate `state_` with `agents.sh` (or any other module
that knows the active fallback list) must keep passing that length as an
argument to the `state_` functions, not make `state_` resolve it on its
own.

## Test pattern for functions with an output contract via variables

The tests of `config/agents.sh` (`tests/agent_codex.bats`,
`agent_claude.bats`, `agent_omp.bats`, `agent_devin.bats`) follow a
uniform, reusable pattern for testing bash functions that expose their
result via contract variables (see the section above):

1. `setup()` does `source config/agents.sh` (the real CLI is never mocked).
2. The test invokes the function directly in the test's own shell (never in
   a subshell, because of the output contract via global variables).
3. The assertions walk `GUBIA_ARGV` with `for i in "${!GUBIA_ARGV[@]}"`
   looking for flags by position, and check
   `GUBIA_PROMPT_MODE`/`GUBIA_OUTPUT_MODE` with direct string comparison.

This is the pattern that tests verifying how the `agents.sh` contract is
consumed from the rest of the engine must follow.

## Editing the catalog stales hardcoded test sentinels (pitfall)

`tests/agent_probe.bats:63` pins a specific fallback entry as a sentinel: the
test "sourcing the catalog without scripts/ next to config/ does not abort"
asserts the `declare -p GUBIA_FALLBACK_MEDIUM` dump contains a literal model
name (originally `*"codex-medium"*`). When an uncommitted edit to
`config/agents.sh` removed `codex-medium` from `GUBIA_FALLBACK_MEDIUM`, that
assertion went stale and the suite reported `140 ok / 1 not ok` — `not ok 8`
in `tests/agent_probe.bats` — an out-of-scope failure unrelated to whatever
task was running.

Symptom: the `[judge regression]` gate fails with `not ok 8` at
`tests/agent_probe.bats:63`, and the failure **recurs across successive
tasks** (observed spanning tasks 05 and 06): the catalog edit stays
uncommitted as user WIP, so every later task's full-suite checkpoint re-hits
the same stale assertion. It is a catalog-edit side effect, not a catalog
error and not the current task's breakage.

Resolution: point the sentinel at an entry that survives the edit
(`codex-medium` → `omp-medium`, which remains in `GUBIA_FALLBACK_MEDIUM`),
then re-run `env -u GUBIA_AGENTS_SH just test` to `141 ok / 0 not ok`. The
catalog edit itself stays uncommitted as a separate concern — it is never
swept into the task's logical commit.

Preventive guidance: before editing `config/agents.sh` model lists, grep the
tests for hardcoded model names (e.g.
`grep -rn 'codex-medium\|codex-low\|omp-medium' tests/`). A removed entry that
a test pins surfaces as a confusing out-of-scope red, not as a catalog
failure. Prefer sentinels that are structural invariants over specific model
names where the contract permits.

### A local out-of-scope red: fix it at first sight, don't re-declare it not assessable

Because the failure is out of scope, `judge.md` makes it Case B — "not a fail
for this block" — and the tempting move is to record `[not assessable]` and
carry on. That closes the individual gate but **defers** the migration's own
closure criterion (a green suite), so the identical red returns on the next
task's `[judge regression]`: this happened verbatim in tasks 05 and 06
(`.gubia/logs/37.out`, `38.out`, `46.out`), and the deferral was flagged at
the time as blocking the closing task (`.gubia/logs/37.out:19`: "This also
blocks task 07's closure (suite must be green)" — even though by then a
one-line sentinel edit sufficed, `.gubia/logs/47.out:3`).

Distinguish the two flavours before choosing:

- the fix lives **outside the repo's tracked state** but is a local, known,
  one-line reconciliation (a stale sentinel) → fix it now, in its own
  `[regression fix]` subtask, and let the block proceed green;
- the cause is genuinely external (a human decision, credentials, an
  uncommitted user change whose *intent* is unclear) → `[not assessable]` is
  right, and the blocker is reported on the subtask line.

Choosing "not assessable" for the first flavour costs one full extra
occurrence of the same failure and leaves the plan's closure gate
unverifiable; choosing the fix for the second mutates user WIP. The judgement
is about whether the reconciliation is *known and local*, not about whether
the file is in the task's Scope.

## Invalid-value sentinels must not collide with valid enum values (methodology)

When a test injects an invalid value to exercise a field's validation path,
the sentinel must be **unambiguously invalid** for that field's enum — never
a value that is valid in another position of the same field. `effort_level`
is validated against `low|medium|high`; the invalid value is `bogus`, **not
`low`**, because `low` is itself a valid level and injecting it would not
exercise the rejection branch at all. The engine-side validation and the
test-side injection are coupled: the rejection message echoes the injected
value back (`invalid value for effort_level: bogus (expected:
low|medium|high)`), so the accepted-values check and the test's injection +
sibling assertion must move in the same commit.

General rule: before renaming or replacing an invalid-value sentinel,
enumerate the field's valid values and assert the chosen sentinel is not
among them; a sentinel that collides with a valid value silently turns the
negative test into a no-op (or a positive test).

Evidence: `tests/gubia_config_validate.bats:211` (injection
`effort_level=bogus`) and `:215` (assertion `invalid value for effort_level:
bogus (expected: low|medium|high)`); `tests/gubia_effort_set.bats:113` (loop
over `bogus`).
