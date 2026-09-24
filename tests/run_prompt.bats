#!/usr/bin/env bats

# Test of the injected prompt composition (plan/04.md: "Implement the
# injected prompt composition: fixed literal header from
# `vault/spec/engine.md` § "Contract injected per iteration" followed by
# the full content of the plan file,
# with no truncation or concatenation of task files").
#
# The observable contract (`vault/spec/engine.md`, "Composition:
# fixed header + `cat <plan>`. Nothing else"):
#
# - The prompt is exactly header + plan content, in that order, with
#   nothing interleaved.
# - The plan enters **whole**: neither truncated nor trimmed to the
#   active line.
# - No concatenation of task files: the content of the linked file does
#   NOT appear in the prompt, not even its first line.
# - The header is literally fixed: it does not interpolate
#   `${GUBIA_ROOT}` or `${GUBIA_PLAN}` (they travel via the
#   environment, see run_export_env.bats) and is identical for every
#   plan.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
}

# Expected header: the fixed one from the contract, line by line, with
# the variables as raw text (`$` escaped so the comparison does not
# depend on the test environment).
expected_header() {
  cat <<'HDR'
## Loop instructions

Each iteration executes **one single** action and stops. Do not chain tasks.

Your plan file is `${GUBIA_PLAN}`, relative to `${GUBIA_ROOT}`
(both variables are in your environment). Its content is pasted below. Links
that appear inside the plan are relative to the **plan's directory**, not to
your current working directory: always compose from `${GUBIA_ROOT}` before
opening anything.

1. **Locate the next subtask**:
   - Walk the plan file top to bottom and find the first `- [ ]`.
   - Every plan entry links to a task file: open it and look inside for the
     first `- [ ]` subtask. There are no inline tasks in the plan.
   - If no `- [ ]` remains anywhere → create `stop.md` in the plan's
     directory, with a brief note ("plan complete, no pending subtasks") and
     **stop**. That file is the signal the engine uses to stop; without it
     the loop keeps iterating even when there's no work left.
2. **Execute that single subtask**:
   - Normal subtask: do it and mark it `[x]`.
   - `[judge]` subtask: invoke the `judge` skill on the repository, passing it
     the instructions from the task file. **Never skipped**: a `[judge]`
     always consumes its iteration, even if you think it's already been
     judged. If the `judge` skill isn't available in your harness, **stop**
     without marking anything: don't improvise it.
   - If the subtask consists of **adding** subtasks or creating a new task
     file: add them and **don't execute them**; creating tasks is the single
     action for the iteration.
   - **Exception (work already done)**: if while inspecting the subtask you
     discover it's already done, mark it `[x]` **naming concrete evidence on
     the same line** (path, command, or artifact that proves it) and
     continue with the next one in this same iteration. If you can't name
     concrete evidence, the exception doesn't apply and the subtask consumes
     the iteration normally. Maximum **3** consecutive skips: on the fourth,
     stop.
3. **Propagate upward**: after marking a subtask, if **all** of the task
   file's subtasks are `[x]`, also mark its entry in the plan.
4. **Success signal**: if and only if you completed the active subtask, end
   your output with a line that is exactly `SUBTASK_COMPLETED=true` (alone
   on its line). On failure, partial progress, or doubt, don't emit that
   token.
5. **Stop**. Don't look for the next subtask, don't chain iterations.
HDR
}

@test "the header is literally the fixed contract text" {
  run run_contract_header
  [ "$status" -eq 0 ]
  expected_header >"$repo/hdr.expected"
  diff -u "$repo/hdr.expected" <(printf '%s\n' "$output")
}

@test "the header does not interpolate the environment even when GUBIA_ROOT/GUBIA_PLAN are exported" {
  export GUBIA_ROOT="$PWD"
  export GUBIA_PLAN="plan/plan.md"
  run run_contract_header
  [ "$status" -eq 0 ]
  # `${GUBIA_ROOT}` and `${GUBIA_PLAN}` arrive literal: the real path
  # does not enter the prompt text.
  grep -qF '${GUBIA_ROOT}' <<<"$output"
  grep -qF '${GUBIA_PLAN}' <<<"$output"
  ! grep -qF "$PWD" <<<"$output"
}

@test "the prompt is exactly header followed by the full plan content" {
  mkdir -p plan/task
  cat >plan/task/04.md <<'TASK'
# Task 04

## Subtareas
- [ ] pendiente uno
TASK
  cat >plan/plan.md <<'PLAN'
# Plan

## Tareas
- [ ] [Task 04](task/04.md)
- [x] [Task 03](task/03.md)
PLAN
  run run_prompt plan/plan.md
  [ "$status" -eq 0 ]
  expected_header >"$repo/hdr.expected"
  { cat "$repo/hdr.expected"; cat plan/plan.md; } >"$repo/prompt.expected"
  diff -u "$repo/prompt.expected" <(printf '%s\n' "$output")
}

@test "no truncation: plan lines far from the active task stay whole" {
  mkdir -p plan/task
  echo '- [ ] [Task 04](task/04.md)' >plan/plan.md
  # 200 filler lines BEFORE the first pending task and the text of the
  # already-completed entry AFTER: the whole cat keeps them all. It is
  # composed in a temp file because redirecting to plan/plan.md while
  # reading from it truncates the read.
  for i in $(seq 1 200); do
    printf '## Filler section %d\n' "$i"
  done >"$repo/filler"
  { cat "$repo/filler"; cat plan/plan.md; echo '- [x] [old task](task/old.md)'; } >"$repo/plan.final"
  mv "$repo/plan.final" plan/plan.md
  run run_prompt plan/plan.md
  [ "$status" -eq 0 ]
  grep -qF '## Filler section 1' <<<"$output"
  grep -qF '## Filler section 200' <<<"$output"
  grep -qF 'old task' <<<"$output"
  [ "$(grep -c 'Filler section' <<<"$output")" -eq 200 ]
}

@test "no concatenation: the task file content does not enter the prompt" {
  mkdir -p plan/task
  printf 'SECRET_TASK_CONTENT\n' >plan/task/04.md
  echo '- [ ] [Task 04](task/04.md)' >plan/plan.md
  run run_prompt plan/plan.md
  [ "$status" -eq 0 ]
  ! grep -qF 'SECRET_TASK_CONTENT' <<<"$output"
  # The plan link's path does travel (it is plan text), the file open
  # does not.
  grep -qF 'task/04.md' <<<"$output"
}
# End to end: the above fixes the shape of the composed prompt; this
# fixes that the `run` subcommand actually injects it into the agent's
# child process. The active agent is the catalog's `agent_probe`, which
# dumps to a file the prompt it receives on stdin: the dump is the
# direct observation of what the agent reads, not an inference about
# what the engine composes.
#
# The prompt section of the dump is extracted by deleting everything up
# to and including the marker (`sed '1,/…/d'`), so what remains is byte
# for byte what entered on stdin.
@test "gubia run injects the composed prompt into the child process stdin" {
  mkdir -p plan/task config
  printf 'SECRET_TASK_CONTENT\n' >plan/task/04.md
  cat >plan/plan.md <<'PLAN'
# Plan

## Tareas
- [ ] [Task 04](task/04.md)
- [x] [Task 03](task/03.md)
PLAN
  # Isolated catalog that resolves the active entry (default level
  # medium, model_index 0) to the repo's real `agent_probe`: the probe
  # is the one that dumps the prompt received on stdin, and that is
  # what this test observes.
  cat >config/agents.sh <<EOF
declare -rA GUBIA_MODELS=([probe-test]='probe fake')
declare -ra GUBIA_FALLBACK_LOW=(probe-test)
declare -ra GUBIA_FALLBACK_MEDIUM=(probe-test)
declare -ra GUBIA_FALLBACK_HIGH=(probe-test)
agent_probe() {
  GUBIA_PROMPT_MODE='stdin'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=("${BATS_TEST_DIRNAME}/../scripts/agent-probe.sh")
  GUBIA_ENV=()
}
EOF
  # `max_iteraciones=1`: the probe exits 0 and creates no stop file, so
  # without a ceiling the engine would spin the default 500 turns. A
  # single iteration is enough for what this test observes.
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
  GUBIA_PROBE_DUMP="${repo}/dump.txt" \
    run "$GUBIA_BIN" run plan/plan.md 1
  [ "$status" -eq 0 ]
  [ -f "${repo}/dump.txt" ]
  sed '1,/^===== prompt =====$/d' "${repo}/dump.txt" >"$repo/prompt.actual"
  { expected_header; cat plan/plan.md; } >"$repo/prompt.expected"
  diff -u "$repo/prompt.expected" "$repo/prompt.actual"
}

@test "the injected prompt brings neither truncation nor the task file content" {
  mkdir -p plan/task config
  printf 'SECRET_TASK_CONTENT\n' >plan/task/04.md
  { printf '# Plan\n\n'
    for i in $(seq 1 200); do printf '## Filler section %d\n' "$i"; done
    printf -- '- [ ] [Task 04](task/04.md)\n'
    printf -- '- [x] [old task](task/old.md)\n'
  } >plan/plan.md
  # Same isolated catalog that resolves to the real `agent_probe`: see
  # the previous test.
  cat >config/agents.sh <<EOF
declare -rA GUBIA_MODELS=([probe-test]='probe fake')
declare -ra GUBIA_FALLBACK_LOW=(probe-test)
declare -ra GUBIA_FALLBACK_MEDIUM=(probe-test)
declare -ra GUBIA_FALLBACK_HIGH=(probe-test)
agent_probe() {
  GUBIA_PROMPT_MODE='stdin'
  GUBIA_OUTPUT_MODE='stdout'
  GUBIA_ARGV=("${BATS_TEST_DIRNAME}/../scripts/agent-probe.sh")
  GUBIA_ENV=()
}
EOF
  # `max_iteraciones=1`: the probe exits 0 and creates no stop file, so
  # without a ceiling the engine would spin the default 500 turns. A
  # single iteration is enough for what this test observes.
  GUBIA_AGENTS_SH="$repo/config/agents.sh" \
  GUBIA_PROBE_DUMP="${repo}/dump.txt" \
    run "$GUBIA_BIN" run plan/plan.md 1
  [ "$status" -eq 0 ]
  sed '1,/^===== prompt =====$/d' "${repo}/dump.txt" >"$repo/prompt.actual"
  [ "$(grep -c 'Filler section' "$repo/prompt.actual")" -eq 200 ]
  grep -qF 'old task' "$repo/prompt.actual"
  ! grep -qF 'SECRET_TASK_CONTENT' "$repo/prompt.actual"
}
