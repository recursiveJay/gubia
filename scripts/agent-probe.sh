#!/usr/bin/env bash
# agent-probe.sh — test agent for the gubia engine (plan/04.md,
# subtask "[create evidence]").
#
# Dumps its environment and the prompt received on stdin to a fixed
# file, and exits 0. It runs no real external process: it's the tool
# the engine uses to verify "absolute path resolution, export of
# `GUBIA_ROOT`/`GUBIA_PLAN`, and literal composition of the injected
# prompt" without touching a real CLI.
#
# The dump file is fixed (`.gubia/agent-probe.dump`), but is NOT
# versioned: it's a dump of the real environment of the machine that
# generates it, different on each checkout and with values that add
# nothing to the repo's history. What's committed —and what makes the
# evidence reproducible from a clean checkout— is the agent itself:
# this script, its `agent_probe` entry in `config/agents.sh`, and the
# invocation from `cmd_run`; anyone can regenerate the dump with a
# `gubia run`.
#
# Each invocation overwrites it entirely (it doesn't accumulate): it's
# a capture of the environment and prompt of ONE invocation, and two
# concatenated captures would be ambiguous evidence.
#
# Dump format (parseable, two sections):
#
#   ===== env =====
#   <output of `env`, one line per variable>
#   ===== prompt =====
#   <full prompt received on stdin>
#
# Matches the `agent_probe` contract documented in
# `vault/conocimiento/agent-invocation-and-catalog-in-gubia.md`:
# starts at the repo root (`scripts/` of the repo), reads the prompt on
# stdin with `cat`, and writes with `printf '%s\n'` (never `echo`,
# which isn't portable with flags like `-n`/`-e`).
set -euo pipefail
shopt -s inherit_errexit

DUMP_FILE="${GUBIA_PROBE_DUMP:-.gubia/agent-probe.dump}"

mkdir -p -- "$(dirname -- "$DUMP_FILE")"
{
  printf '%s\n' '===== env ====='
  env
  printf '%s\n' '===== prompt ====='
  cat
} >"$DUMP_FILE"

exit 0