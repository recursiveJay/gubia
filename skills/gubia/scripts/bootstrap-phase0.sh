#!/usr/bin/env bash
set -euo pipefail

plan_file="${1:-plan/plan.md}"
plan_dir="$(dirname "$plan_file")"

# Tasks live in `task/`, next to the plan file. The path is not derived
# from the plan's name: the link written in the plan is the only source
# of truth.
task_dir="$plan_dir/task"
task00="$task_dir/00.md"
entry="- [ ] [00. Drain phase 0](task/00.md)"

if [[ ! -f "$plan_file" ]]; then
  echo "missing plan file: $plan_file" >&2
  exit 1
fi

mkdir -p "$task_dir"

cat >"$task00" <<'EOF'
# Task 00 — Drain phase 0

Mandatory header note: this reserved file (task 00) only orchestrates
breaking the plan down into product tasks. It is not a product task and
is excluded from simplification, context validation, effort, judge
planning, cleanup, and commits; a second phase0 pass does not reprocess
it or reuse it as a product task either.

## Subtasks
- [ ] Breakdown — Break the plan file down into task files starting at 01, without reusing or reprocessing task 00. Read the plan and the local knowledge (vault/ or skills) and materialize task files 01..N by direct write, following the structure of `skills/gubia/scaffold_task.md`. Then queue, in this same file, the following phases (simplification, context validation, effort, judge planning, commits) as subtasks.
- [ ] Simplification — Split subtasks that don't fit in one iteration: screen by text and, for each candidate, replace it with simple subtasks in the same file.
- [ ] Context validation — Revalidate that the `Linked context` of each product task file is still current against the repo's current state; fix or remove stale links.
- [ ] Effort — Interleave `[effort …]` subtasks that change the model's capability into each product task file, as standalone subtasks (never an inline tag).
- [ ] Judge planning — Invoke `/judge plan` on each product task file to insert the missing `[judge]` and `[create evidence]` checkpoints.
- [ ] Cleanup — Leave the plan file as a lean index: keep the objective/context, links, and `[x]` entries; remove detail duplicated in the tasks.
- [ ] Commits — Only if the repo is git: interleave commit subtasks after each judge block of each product task file. If it isn't git, mark this subtask `[x]` with no further effect.
EOF

tmp_file="$(mktemp)"
awk -v entry="$entry" '
  BEGIN { inserted = 0; in_tasks = 0 }
  $0 == entry { next }
  {
    print
    if ($0 == "## Tareas" || $0 == "## Tasks") {
      print ""
      print entry
      inserted = 1
      in_tasks = 1
      next
    }
    if (in_tasks && $0 ~ /^- \[[ x]\]/) {
      in_tasks = 0
    }
  }
  END {
    if (!inserted) {
      print ""
      print "## Tasks"
      print ""
      print entry
    }
  }
' "$plan_file" >"$tmp_file"
mv "$tmp_file" "$plan_file"

printf 'materialized %s and updated %s\n' "$task00" "$plan_file"
