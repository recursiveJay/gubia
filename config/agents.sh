# shellcheck shell=bash
# shellcheck source=/dev/null
#
# agents.sh — gubia engine's global agent catalog.
#
# Sourceable translation of `destilado/referencia/agents.toml` (see
# `destilado/catalogo-agentes.md`): one function per agent —
# `agent_codex`, `agent_claude`, `agent_omp`, `agent_devin` — that
# builds the invocation argv/env, and model/fallback arrays per
# level (low/medium/high).
#
# Human/engine config, never an iteration agent's: it gets sourced
# (never parsed with an allowlist, unlike `.gubia/state.env`). It
# lives in the repo as `config/agents.sh`; the engine resolves it in
# order: `GUBIA_AGENTS_SH` from the environment, else the local
# `config/agents.sh`, and if that doesn't exist, the copy installed
# at `~/.config/gubia/agents.sh` (installing it there is a manual
# user step, not automated).
#
# The `source=/dev/null` guard in the header is for the `source`
# that `gubia` does on the copy installed at `~/.config/gubia/`: the
# linter can't resolve that path at lint time.

# ---------------------------------------------------------------------------
# Models — literal translation of the [models.*] entries in agents.toml.
# Key: catalog entry name; value: "agent model", as-is.
# SC2034: the arrays are consumed after `source` from the engine, not in
# this file; shellcheck will always flag them as unused.
# ---------------------------------------------------------------------------

# shellcheck disable=SC2034
declare -rA GUBIA_MODELS=(
    [codex-low]="codex gpt-5.6-luna"
    [codex-medium]="codex gpt-5.6-terra"
    [claude-medium]="claude sonnet"
    [claude-high]="claude opus"
    [omp-low]="omp deepseek-v4-flash:0731"
    [omp-medium]="omp deepseek-v4-pro:0813"
    [omp-high]="omp glm-5.2:cloud"
    [devin-low]="devin swe-1.6-fast"
    [devin-medium]="devin swe-1.7-lightning"
    [devin-high]="devin opus"
    [devin-high-glm]="devin glm-5.2"
)

# ---------------------------------------------------------------------------
# Fallback lists — literal translation of [fallback.default.*]. Order is
# preserved: model_index (.gubia/state.env) indexes into these lists.
# ---------------------------------------------------------------------------

# shellcheck disable=SC2034
declare -ra GUBIA_FALLBACK_LOW=(
    omp-low
    codex-low
    devin-low
)

# shellcheck disable=SC2034
declare -ra GUBIA_FALLBACK_MEDIUM=(
    codex-medium
    omp-medium
    claude-medium
    devin-medium
)

# shellcheck disable=SC2034
declare -ra GUBIA_FALLBACK_HIGH=(
    omp-high
    claude-high
    devin-high
    devin-high-glm
)

# Valid effort levels, in the order of [effort].sequence.
# shellcheck disable=SC2034
declare -ra GUBIA_EFFORT_SEQUENCE=(low medium high)

# ---------------------------------------------------------------------------
# Per-agent functions — literal translation of the [agents.*] entries.
#
# Common contract (consumed by the engine, task 05/06): each function
# receives the concrete values that replace the agents.toml placeholders
# and fills, in the caller's scope:
#
#   GUBIA_ARGV          array with the full argv, command included.
#   GUBIA_ENV           array of KEY=VALUE pairs (empty if env = []).
#   GUBIA_PROMPT_MODE   "stdin" or "file": how the prompt enters the CLI.
#   GUBIA_OUTPUT_MODE   "stdout" or "file": where the output to capture ends up.
#
# The TOML's `when`/`unset_when_skipped` conditional logic becomes an
# `if` inside the function: that's what drove this to be bash rather
# than plain env (see `catalogo-agentes.md`).
# ---------------------------------------------------------------------------

# codex — prompt via stdin, output to a file ({console_output}), effort
# via `-c model_reasoning_effort`, bypass with --dangerously… (literal,
# CLI-specific). `{no_thinking_codex}` only expands when thinking=false.
agent_codex() {
  if (( $# != 4 )); then
    printf 'agent_codex: usage: agent_codex <model> <effort> <thinking> <console_output>\n' >&2
    return 2
  fi
  local model="$1" effort="$2" thinking="$3" console_output="$4"

  GUBIA_PROMPT_MODE='stdin'
  GUBIA_OUTPUT_MODE='file'
  GUBIA_ARGV=(
    codex
    exec
    --dangerously-bypass-approvals-and-sandbox
    --skip-git-repo-check
    -m "$model"
    -o "$console_output"
    -c "model_reasoning_effort=\"$effort\""
  )
  # {no_thinking_codex}: only when thinking=false (when true, it expands
  # to nothing — two entries with the same name in the TOML).
  if [[ "$thinking" == "false" ]]; then
    GUBIA_ARGV+=(
      -c 'model_reasoning_summary="none"'
      -c 'hide_agent_reasoning=true'
    )
  fi
  GUBIA_ARGV+=(-)

  GUBIA_ENV=()
}

# claude — prompt via stdin, output to stdout, effort wired two ways: the
# `--effort` flag in argv and the CLAUDE_CODE_EFFORT_LEVEL env var (both
# wire {effort}, as in the TOML). CLAUDE_CODE_DISABLE_THINKING is only
# exported when thinking=false; with true it's left unset (unset_when_skipped).
agent_claude() {
  if (( $# != 3 )); then
    printf 'agent_claude: usage: agent_claude <model> <effort> <thinking>\n' >&2
    return 2
  fi
  local model="$1" effort="$2" thinking="$3"

  GUBIA_PROMPT_MODE='stdin'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=(
    claude
    --permission-mode
    bypassPermissions
    --model "$model"
    --effort "$effort"
    -p
  )

  GUBIA_ENV=("CLAUDE_CODE_EFFORT_LEVEL=$effort")
  if [[ "$thinking" == "false" ]]; then
    GUBIA_ENV+=("CLAUDE_CODE_DISABLE_THINKING=1")
  fi
}

# omp — prompt via file ({prompt_file}), output to stdout, effort via
# `--thinking` (wires {effort}, as in the TOML). Bypass with
# --approval-mode=yolo plus --no-session (CLI literals). When
# thinking=false, the {no_thinking_omp} placeholder appends `--thinking off`
# afterwards (two --thinking flags: the second one wins); with true it
# expands to nothing.
agent_omp() {
  if (( $# != 4 )); then
    printf 'agent_omp: usage: agent_omp <model> <effort> <thinking> <prompt_file>\n' >&2
    return 2
  fi
  local model="$1" effort="$2" thinking="$3" prompt_file="$4"

  GUBIA_PROMPT_MODE='file'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=(
    omp
    --approval-mode=yolo
    --no-session
    --model "ollama/$model"
    --thinking "$effort"
  )
  # {no_thinking_omp}: only when thinking=false (when true, it expands
  # to nothing — two entries with the same name in the TOML).
  if [[ "$thinking" == "false" ]]; then
    GUBIA_ARGV+=(--thinking off)
  fi
  GUBIA_ARGV+=(-p "@$prompt_file")

  GUBIA_ENV=()
}

# devin — prompt via file ({prompt_file}), output to stdout. The CLI
# doesn't expose an effort flag or env var (only interactive Alt+T, which
# doesn't apply to -p), so it doesn't wire {effort} or a thinking toggle,
# unlike codex/claude/omp (literal comment from the TOML). Bypass with
# --permission-mode dangerous (CLI literal).
agent_devin() {
  if (( $# != 2 )); then
    printf 'agent_devin: usage: agent_devin <model> <prompt_file>\n' >&2
    return 2
  fi
  local model="$1" prompt_file="$2"

  GUBIA_PROMPT_MODE='file'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=(
    devin
    --permission-mode
    dangerous
    --respect-workspace-trust
    false
    --model "$model"
    --prompt-file "$prompt_file"
    -p
  )

  GUBIA_ENV=()
}

# agent_probe — engine test agent (plan/04.md, subtask
# "[create evidence]"). Not a real CLI: it's the tool the engine uses to
# verify itself without touching an external agent.
#
# It follows the same contract as the real agents (the same function
# that the `invoke_` from task 05 will consume):
#
# - Transport via stdin (GUBIA_PROMPT_MODE='stdin'): the composed
#   prompt (`run_contract_header` + `cat <plan>`, the literal
#   composition from `motor-contrato.md`) comes in through its stdin.
# - Output to stdout (GUBIA_OUTPUT_MODE='stdout').
# - No argv or env of its own (single-element GUBIA_ARGV, empty
#   GUBIA_ENV): the binary takes no options.
#
# The function only BUILDS the invocation (argv/env/modes), just like
# the real functions: running the command is the invocation layer's
# job. The dumped executable is a repo script
# (`scripts/agent-probe.sh`), committed so the evidence is reproducible
# from a clean checkout; it's launched by its absolute path so it works
# regardless of the engine process's cwd.
#
# The model/effort/thinking arguments are decorative: the probe
# neither wires nor uses any of them (the signature takes the same
# first three arguments as the real stdin agents, so the engine can
# call it without special-casing once task 05 lands).
agent_probe() {
  if (( $# < 3 )); then
    printf 'agent_probe: usage: agent_probe <model> <effort> <thinking>\n' >&2
    return 2
  fi

  # Absolute path of the executable, resolved on first invocation and
  # cached. It used to be computed at top level on source: the `cd`
  # into `../scripts` aborted the whole source when `scripts/` doesn't
  # exist next to `config/` (a workspace that only copied the
  # catalog), taking the real fallback lists down with it. The probe
  # is a test agent that the loop never selects: its path should only
  # be resolved when it's actually invoked.
  #
  # It's derived from this file's own location, not the cwd of the
  # process that sources it: `agents.sh` can be sourced from any
  # directory (the tests do this, and the engine will do it from the
  # project root), and `GUBIA_ARGV` runs later, in a cwd this function
  # doesn't control — a relative path here would be a time bomb. The
  # `cd`+`pwd` in a subshell is what makes it truly absolute; the `./`
  # guard covers `source agents.sh` without a slash.
  if [[ -z "${config_probe_abs:-}" ]]; then
    config_probe_abs="$(
      probe_self="${BASH_SOURCE[0]}"
      [[ "$probe_self" == */* ]] || probe_self="./$probe_self"
      cd -- "${probe_self%/*}/../scripts" && pwd
    )/agent-probe.sh"
  fi

  GUBIA_PROMPT_MODE='stdin'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=(
    "${config_probe_abs}"
  )
  GUBIA_ENV=()
}
