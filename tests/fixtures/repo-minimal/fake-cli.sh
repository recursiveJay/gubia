#!/usr/bin/env bash
#
# fake-cli.sh — fake agent CLI of the `repo-minimal` fixture (task 10).
#
# Sibling of the fake CLIs of the e2e suites of tasks 04-06
# (`tests/gubia_run_max_iterations.bats`, `tests/gubia_run_stop_flock.bats`):
# scripted exit codes, zero network and zero credentials, deterministic.
#
# Contract it honors (the one the engine's `invoke_` layer produces):
# - The prompt arrives via file (argv `--prompt <file>`) when the catalog
#   invokes it with `GUBIA_PROMPT_MODE='file'`. ITS CONTENT IS NOT
#   INTERPRETED: the subtask to drain is resolved over the plan on disk
#   (`GUBIA_PLAN` relative to `GUBIA_ROOT`, both in the iteration's
#   environment), just as a real agent navigating the repo would.
# - `GUBIA_OUTPUT_MODE='stdout'`: the engine captures the output in
#   `.gubia/logs/<iter>.out`; here only the success token is emitted.
# - Scripted exit codes: 0 = iteration completed; 1 = invalid usage
#   (missing prompt, missing plan or task, unmapped effect).
#
# What it does in the test repo — simulates the contract's iterator
# (`motor-contrato.md`), ONE subtask per invocation:
#
# 1. Witness: appends a `tick` line to `$GUBIA_FIXTURE_LOG/marker.log`
#    (equivalent to the `agent.marker` of the 04-06 tests); the tests count
#    real loop turns by counting lines.
# 2. Drains ONE subtask: first `- [ ]` of the plan with a link to a task
#    that still has a `- [ ]` inside, first `- [ ]` of that task; applies
#    its effect (fixed mapping by file name, `apply_task`) and marks it
#    `[x]` with the evidence named on the line. If the task is left with no
#    pending items, propagates its plan entry to `[x]`.
# 3. If no `- [ ]` remains in the plan nor in its tasks (step 1 of the
#    contract): creates `stop.md` next to the plan with the brief note.
# 4. Emits `SUBTAREA_COMPLETADA=true`.
#
# The effects create exactly the files the e2e tests verify (`greeting.txt`,
# `output/echo.txt`, `done.flag`). The identity of the task file is the key
# of the mapping, never the subtask text (robust to rewording). A task with
# no mapped effect dies with exit 1 — the engine reads it as an iteration
# failure and rotates/aborts, the correct signal for a badly extended
# fixture.
set -euo pipefail
export LC_ALL=C

# The fixture accepts both the file prompt of omp/devin (the catalog
# function is the one that wires it into its argv) and the probe's stdin.
prompt_file=
prompt_from_stdin=
# `--prompt <path>` is also accepted so the CLI is usable by hand.
args=("$@")
for ((ai = ${#args[@]} - 1; ai >= 0; ai--)); do
  arg="${args[ai]}"
  if [[ "$arg" == "--prompt" ]]; then
    prompt_file="${args[ai + 1]:-}"
    break
  fi
  prompt_file="$arg"
done
if [[ -z "$prompt_file" ]]; then
  prompt_from_stdin="$(mktemp)"
  trap 'rm -f -- "$prompt_from_stdin"' EXIT
  cat >"$prompt_from_stdin"
  prompt_file="$prompt_from_stdin"
fi
if [[ ! -f "$prompt_file" ]]; then
  printf 'fake-cli: prompt does not exist: %s\n' "$prompt_file" >&2
  exit 1
fi

# Root of the test repo: the engine exports it (GUBIA_ROOT); every effect
# is anchored to it, not to the cwd inherited from the engine.
root="${GUBIA_ROOT:-$(pwd -P)}"
if [[ ! -d "$root" ]]; then
  printf 'fake-cli: GUBIA_ROOT is not a directory: %s\n' "$root" >&2
  exit 1
fi

# --- Iteration witness ------------------------------------------------------

# Configurable directory so the tests can isolate it; outside `.gubia/` so
# it does not mix with the engine's state nor leak into its counts.
marker_dir="${GUBIA_FIXTURE_LOG:-$root/.fixture-log}"
mkdir -p -- "$marker_dir"
printf 'tick\n' >>"$marker_dir/marker.log"

# --- Trivial effects per task file ------------------------------------------

# Runs with cwd = fixture root (prior cd of the caller).
apply_task() {
  case "${task_file##*/}" in
    00.md)
      printf 'hello fixture\n' >greeting.txt
      ;;
    01.md)
      mkdir -p -- output
      printf 'fixture echo\n' >output/echo.txt
      ;;
    02.md)
      printf 'done\n' >done.flag
      ;;
    *)
      printf 'fake-cli: no mapped effect for %s\n' "${task_file##*/}" >&2
      return 1
      ;;
  esac
}

# Detects whether a file has any `- [ ]` and leaves its (1-based) number in
# `open_no`. Returns 1 if there is none.
first_open_line() {
  local file="$1" line no=0
  open_no=
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((no++)) || true
    if [[ "$line" == *'- [ ]'* ]]; then
      open_no="$no"
      return 0
    fi
  done <"$file"
  return 1
}

# Extracts the markdown link path from a plan line and resolves it against
# the plan's directory (the flat plan grammar: ``](path)``).
link_target() {
  local dir="$1" line="$2" link
  link="${line#*](}"
  link="${link%%)*}"
  link="${link#"${link%%[![:space:]]*}"}"
  link="${link%"${link##*[![:space:]]}"}"
  printf '%s\n' "$dir/$link"
}

# Marks subtask N as `[x]` with the evidence named on the line (the
# "work already done" exception of the contract requires concrete evidence).
mark_done() {
  local file="$1" no="$2"
  sed -i -e "${no}s/- \[ \]/- [x]/" -e "${no}s/\$/ — done by fake-cli/" "$file"
}

# --- Draining ONE subtask ----------------------------------------------------

plan_file="$root/${GUBIA_PLAN:-plan/plan.md}"
if [[ ! -f "$plan_file" ]]; then
  printf 'fake-cli: plan does not exist: %s\n' "$plan_file" >&2
  exit 1
fi
plan_dir="$(cd -- "$(dirname -- "$plan_file")" && pwd -P)"

# 1) First pending subtask: first `- [ ]` of the plan whose linked task in
#    turn has a `- [ ]` inside. Entries already marked `[x]` with a task
#    that has pending items (truncated propagation after a relaunch) are
#    traversed the same way.
task_file=
open_no=
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    *']('*'.md)'*) ;;
    *) continue ;;
  esac
  candidate="$(link_target "$plan_dir" "$line")"
  if [[ -f "$candidate" ]] && first_open_line "$candidate"; then
    task_file="$candidate"
    break
  fi
done <"$plan_file"

# 2) No `- [ ]` in the plan nor in the linked tasks: the contract (step 1)
#    creates `stop.md` next to the plan with the brief note. With the stop
#    file present the engine cuts before invoking again.
if [[ -z "$task_file" ]]; then
  printf 'plan completo, sin subtareas pendientes\n' >"$plan_dir/stop.md"
  printf 'SUBTAREA_COMPLETADA=true\n'
  exit 0
fi

# 3) Effect + marking of the task's first pending subtask.
(cd -- "$root" && apply_task) || exit 1
mark_done "$task_file" "$open_no"

# 4) Upward propagation (step 3 of the contract): task with no pending
#    items → its plan entry also to `[x]`. The entry is the one linking to
#    this task; the search completes first (over the untouched file) and
#    the `sed` writes afterwards (SC2094: never read and write the same
#    file in the same loop).
if ! first_open_line "$task_file"; then
  entry_no=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((entry_no++)) || true
    [[ "$line" == *']('*'.md)'* ]] || continue
    target="$(link_target "$plan_dir" "$line")"
    if [[ "$target" == "$task_file" ]]; then
      entry_line="$entry_no"
      break
    fi
  done <"$plan_file"
  if [[ -n "${entry_line:-}" ]]; then
    sed -i "${entry_line}s/- \[ \]/- [x]/" "$plan_file"
  fi
fi
printf 'SUBTAREA_COMPLETADA=true\n'
exit 0
