# Agent catalog (`config/agents.sh`)

Spec of the engine's global agent catalog, written against the live code
of `config/agents.sh` (275 lines) and its consumption in `gubia`. It
replaces the historical v1 reference, which omitted `agent_probe`; here
every fact is anchored to the live file.

## What it is

`config/agents.sh` is the engine's global agent config: a **sourceable**
file (not parsed) that declares models, per-effort-level fallback lists,
and one bash function per agent that builds the invocation. It's touched
by the human and the engine, never by an iteration agent. It's bash on
purpose — functions, associative arrays, and conditional logic that
doesn't fit in plain env — and it **is sourced**, unlike
`.gubia/state.env` (which is read with an allowlist because the agent
writes it).

## File resolution

The engine resolves the catalog path once at startup (`gubia:47`), in
order:

1. `GUBIA_AGENTS_SH` from the environment, if set.
2. The local `config/agents.sh` (versioned in the repo).
3. The copy installed at `~/.config/gubia/agents.sh`.

Installing the copy at `~/.config/gubia/` is a manual user step, not
automated. The `source=/dev/null` guard in the file's header is for the
`source` that `gubia` does over that installed copy: the linter cannot
resolve the path at lint time.

## Models (`GUBIA_MODELS`)

`declare -rA` associative array (`config/agents.sh:32`) with **11
entries**. The key is the catalog entry's name; the value is the literal
pair `"agent model"`, as-is:

| Key | Agent | Model |
|---|---|---|
| `codex-low` | codex | `gpt-5.6-luna` |
| `codex-medium` | codex | `gpt-5.6-terra` |
| `claude-medium` | claude | `sonnet` |
| `claude-high` | claude | `opus` |
| `omp-low` | omp | `deepseek-v4-flash:0731` |
| `omp-medium` | omp | `deepseek-v4-pro:0813` |
| `omp-high` | omp | `glm-5.2:cloud` |
| `devin-low` | devin | `swe-1.6-fast` |
| `devin-medium` | devin | `swe-1.7-lightning` |
| `devin-high` | devin | `opus` |
| `devin-high-glm` | devin | `glm-5.2` |

The pair is split in `run_resolve_agent` (`gubia:868`): `agent="${entry%%
*}"` and `model="${entry#* }"`. The agent derives the function name
(`agent_<agent>`); the model is the identifier that function receives.

## Fallback lists (`GUBIA_FALLBACK_*`)

Three `declare -ra` arrays (`config/agents.sh:52-72`), one per effort
level. `model_index` (from `state.env`) indexes **into** the active
level's list, so the lists can have different lengths and the index is
only meaningful together with `effort_level`:

| Level | Array | Entries (order preserved) |
|---|---|---|
| low | `GUBIA_FALLBACK_LOW` | `omp-low`, `codex-low`, `devin-low` (3) |
| medium | `GUBIA_FALLBACK_MEDIUM` | `codex-medium`, `omp-medium`, `claude-medium`, `devin-medium` (4) |
| high | `GUBIA_FALLBACK_HIGH` | `omp-high`, `claude-high`, `devin-high`, `devin-high-glm` (4) |

The order is the rotation order: a failure advances `model_index` to the
next one, and wraps back to `0` after the last (`gubia:289`
`state_rotate_model_index`). The streak sentinel aborts with
`fallback-exhausted` (exit 3) if the rotation returns to the index of the
first failure with no successful iteration in between (`gubia:814`).
`gubia effort set` resets `model_index` to `0` on a level change, because
the index belongs to the new list.

The active list's length is queried by `run_active_len` (`gubia:955`),
which composes the array name from `effort_level` (already constrained
to `low|medium|high` by `state_validate`, so the indirection never points
at an arbitrary name).

## Resolving the active entry

`run_resolve_agent` (`gubia:850`) is the pure operation that, given
`effort_level` and `model_index`, selects the round's actual CLI:

1. `list_name="GUBIA_FALLBACK_${active_effort^^}"` — if the catalog
   doesn't define that array, exit 2 (broken catalog).
2. `key="${list[$active_index]}"` — the list entry.
3. `entry="${GUBIA_MODELS[$key]}"` — if the key isn't in the map, exit 2.
4. `agent="${entry%% *}"`, `model="${entry#* }"`, function
   `agent_<agent>`.
5. `declare -F "agent_<agent>"` — if the catalog doesn't define the
   function, exit 2.

A fallback key with no model entry, or an agent with no function, is a
broken catalog: there's no invocation that can be built, so it aborts
(it doesn't rotate). The `model_index` range guard doesn't live here:
that's the non-aborting policy of `state_guard_model_index`, which
resets to `0` with a warning.

## Common contract of agent functions

Each function receives the concrete values that replace the historical
placeholders and fills, **in the caller's scope**, four variables that
the invocation layer (`invoke_prepare`, `gubia:1101`) consumes:

| Variable | Type | Meaning |
|---|---|---|
| `GUBIA_ARGV` | array | full argv, command included |
| `GUBIA_ENV` | array | `KEY=VALUE` pairs (empty if no env) |
| `GUBIA_PROMPT_MODE` | `stdin`\|`file` | how the prompt reaches the CLI |
| `GUBIA_OUTPUT_MODE` | `stdout`\|`file` | where the output to capture ends up |

The function **only builds** the invocation; running the command is
`invoke_agent`'s job. The historical conditional logic (`when`/
`unset_when_skipped`) is an `if` inside the function — that's what drove
the catalog to be bash instead of plain env.

`invoke_prepare` sets the two files that some functions receive as an
argument (the prompt and, for codex, the console destination) **before**
calling the function: the prompt can't just be appended to the end of
`GUBIA_ARGV`, because omp and devin wire it with their own flags and
codex instead receives the output destination.

## Per-agent profile

### `agent_codex` (`config/agents.sh:98`)

- **Transport**: prompt via stdin, output to a **file**
  (`{console_output}`, wired with `-o`).
- **Args**: `<model> <effort> <thinking> <console_output>`.
- **Effort**: `-c "model_reasoning_effort=\"$effort\""`.
- **Thinking**: only when `thinking=false` does it add
  `-c 'model_reasoning_summary="none"'` and `-c
  'hide_agent_reasoning=true'`; with `true` it expands to nothing.
- **Bypass**: `--dangerously-bypass-approvals-and-sandbox`
  `--skip-git-repo-check` (CLI literals, different per agent).
- **Env**: empty. The prompt enters through the final `-` in the argv.

### `agent_claude` (`config/agents.sh:133`)

- **Transport**: prompt via stdin, output to stdout.
- **Args**: `<model> <effort> <thinking>`.
- **Effort**: double path — the `--effort "$effort"` flag in argv **and**
  the `CLAUDE_CODE_EFFORT_LEVEL=$effort` env var (both wire the effort).
- **Thinking**: `CLAUDE_CODE_DISABLE_THINKING=1` is only exported when
  `thinking=false`; with `true` it's left undefined
  (`unset_when_skipped`).
- **Bypass**: `--permission-mode bypassPermissions`.
- **Env**: `CLAUDE_CODE_EFFORT_LEVEL` (always) +
  `CLAUDE_CODE_DISABLE_THINKING` (only when false).

### `agent_omp` (`config/agents.sh:163`)

- **Transport**: prompt via a **file** (`{prompt_file}`, wired with `-p
  "@$prompt_file"`), output to stdout.
- **Args**: `<model> <effort> <thinking> <prompt_file>`.
- **Effort**: `--thinking "$effort"`.
- **Thinking**: when `thinking=false`, the placeholder adds `--thinking
  off` **after** the effort one — two `--thinking` flags, the second
  wins; with `true` it expands to nothing.
- **Bypass**: `--approval-mode=yolo` `--no-session`.
- **Model**: the argv prefixes it with `ollama/` (`--model
  "ollama/$model"`).
- **Env**: empty.

### `agent_devin` (`config/agents.sh:194`)

- **Transport**: prompt via a **file** (`--prompt-file "$prompt_file"`),
  output to stdout.
- **Args**: `<model> <prompt_file>` — **no** effort or thinking.
- **Effort**: **not wired**. Devin's CLI exposes no flag or env var for
  reasoning level on `-p` (only interactive Alt+T, which doesn't apply).
  It's not a catalog oversight: the function deliberately receives fewer
  arguments than the others.
- **Thinking**: no toggle, for the same reason.
- **Bypass**: `--permission-mode dangerous`
  `--respect-workspace-trust false`. The workspace-trust flag is the
  part that actually gates folder trust; `--permission-mode dangerous`
  alone does **not** cover it (see `installation.md`'s folder-trust
  rule).
- **Env**: empty.

## `agent_probe` (`config/agents.sh:240`)

Not a real CLI: it's the tool the engine uses to verify itself without
touching an external agent. The historical v1 reference omitted it;
here it's documented because it lives in the catalog.

It fulfills the same contract as the real agents — the same function
that `invoke_` consumes — but:

- **Transport**: stdin (`GUBIA_PROMPT_MODE='stdin'`), stdout
  (`GUBIA_OUTPUT_MODE='stdout'`).
- **argv**: a single element, the **absolute** path to the executable
  (`scripts/agent-probe.sh`, committed for reproducible evidence from a
  clean checkout). **No env of its own** (`GUBIA_ENV=()`).
- **Decorative args**: the signature receives `<model> <effort>
  <thinking>` (the same first three as the real stdin agents) so the
  engine can call it without special-casing, but it **doesn't wire or
  use them**: the binary takes no options.
- **Lazy path**: the absolute path is resolved on the first invocation
  and cached in `config_probe_abs`, derived from `${BASH_SOURCE[0]}`
  (not from the sourcer's cwd). It used to be computed when the catalog
  was sourced, which aborted the entire `source` when `scripts/` didn't
  exist next to `config/` — a workspace that only copied the catalog
  would take down the real fallback lists with it. The `cd`+`pwd` in a
  subshell is what makes the path genuinely absolute.

`agent_probe` **is not a loop agent**: no fallback list references it,
and `config validate` doesn't require it (see below). It's a manual pick
for testing the catalog and the invocation contract.

## `config validate` and the catalog

`gubia config validate` (`gubia:2070` `cmd_config_validate`) sources the
catalog and checks three things, accumulating every failure before
exiting with exit 2:

1. **Agent functions** (`config_agent_functions`, `gubia:1717`):
   `declare -F` for the **four** real functions — `agent_codex`,
   `agent_claude`, `agent_omp`, `agent_devin`. `declare -F` is used
   instead of `type`/`command -v`: the question is "does a function
   exist?", and an executable or alias with the same name would pass
   the check without the catalog defining anything. `agent_probe`
   **isn't included**: it's the test agent, not a catalog CLI, and
   requiring it would turn a perfectly valid user `agents.sh` into a
   broken config.
2. **`state.env` scalars**: the 6 keys present and in-domain (see
   `engine.md`).
3. **Installed skills** (`config_validate_skills`, `gubia:1989`): walks
   the active level's fallback list, dedups by agent, and checks that
   each agent has its known skills layout
   (`config_harness_skills_dir`, `gubia:1935`) with the **`gubia` and
   `judge`** skills installed (`config_required_skills=(gubia judge)`,
   `gubia:1952`). That's **two** skills required by the loop, not
   three: `scribe` is synced (see `installation.md`) but isn't a
   requirement for `run`.

Per-harness skills layouts:

| Agent | Skills directory |
|---|---|
| claude | `~/.claude/skills` |
| codex | `~/.codex/skills` |
| omp | `~/.omp/agent/skills` |
| devin | `~/.config/devin/skills` |

An agent in the fallback list whose layout is unknown is reported and
skipped (the rest of the list can still be fine). `config validate`
**does not take the `flock`**: it must be able to validate with a loop
running against the same plan.
