#!/usr/bin/env bats

# Test of the phase-0 effort placement scripts:
#   skills/gubia/scripts/effort-plan.sh    (transition planner, TSV + --apply)
#   skills/gubia/scripts/effort-expand-00.sh (manifest bullet expansion)
# per vault/spec/effort-placement.md.
#
# Only observable behavior is asserted: the exact TSV lines, the exact
# inserted bullets, byte-identical idempotency, and the exit-3 abort.
# Internal wording is never pinned beyond what the spec fixes.

PLAN_SH="${BATS_TEST_DIRNAME}/../skills/gubia/scripts/effort-plan.sh"
EXPAND_SH="${BATS_TEST_DIRNAME}/../skills/gubia/scripts/effort-expand-00.sh"

setup() {
  repo="$(mktemp -d)"
}

teardown() {
  rm -rf "$repo"
}

# A product task file exercising every rule: a keyword-less first bullet
# (floors to medium), an unmatched bullet, a `[judge]` (high), a restore
# after it, a `low` keyword, and a trailing `[scribe]` (medium).
write_fixture() {
  cat >"$1" <<'EOF'
# Task NN

## Subtasks

- [ ] Validate the linked context of this file against the repo's current state.
- [ ] Something that matches no keyword at all.
- [ ] Implement the feature.
- [ ] [judge] The thing is correct
  - Scope: the implementation
- [ ] Add a test.
- [ ] Scaffold the crate.
- [ ] Commit — commit the changes.
- [ ] [scribe] Distill the learning.
EOF
}

@test "read-only prints the exact transitions and the # unmatched section" {
  write_fixture "$repo/task.md"

  # The transitions are TSV, one per line, `n` counting only the `- [ ]`
  # bullets. `[judge]` raises to high; the next content subtask restores.
  run "$PLAN_SH" "$repo/task.md"
  [ "$status" -eq 0 ]
  diff - <(printf '%s\n' "$output") <<'EOF'
0	medium	initial (floor: context validation)
3	high	before [judge]
4	medium	restore: next=add
5	low	scaffold
7	medium	scribe
# unmatched
0	Validate the linked context of this file against the repo's current state.
1	Something that matches no keyword at all.
EOF
}

@test "--apply inserts the exact effort bullets at the transition points" {
  write_fixture "$repo/task.md"

  run "$PLAN_SH" "$repo/task.md" --apply
  [ "$status" -eq 0 ]

  diff - "$repo/task.md" <<'EOF'
# Task NN

## Subtasks

- [ ] [effort medium] Fix the model's capability: run `gubia effort set medium`.
- [ ] Validate the linked context of this file against the repo's current state.
- [ ] Something that matches no keyword at all.
- [ ] Implement the feature.
- [ ] [effort high] Fix the model's capability: run `gubia effort set high`.
- [ ] [judge] The thing is correct
  - Scope: the implementation
- [ ] [effort medium] Fix the model's capability: run `gubia effort set medium`.
- [ ] Add a test.
- [ ] [effort low] Fix the model's capability: run `gubia effort set low`.
- [ ] Scaffold the crate.
- [ ] Commit — commit the changes.
- [ ] [effort medium] Fix the model's capability: run `gubia effort set medium`.
- [ ] [scribe] Distill the learning.
EOF
}

@test "--apply is idempotent: a second run leaves the file byte-identical" {
  write_fixture "$repo/task.md"
  "$PLAN_SH" "$repo/task.md" --apply >/dev/null
  cp "$repo/task.md" "$repo/before"

  run "$PLAN_SH" "$repo/task.md" --apply
  [ "$status" -eq 0 ]

  cmp "$repo/before" "$repo/task.md"
}

@test "--apply aborts with exit 3 and leaves the file untouched when a content bullet is [x]" {
  write_fixture "$repo/task.md"
  "$PLAN_SH" "$repo/task.md" --apply >/dev/null
  cp "$repo/task.md" "$repo/before"

  # Drain one content bullet: phase 0 has started, so --apply must refuse.
  sed -i 's/^- \[ \] Validate/- [x] Validate/' "$repo/task.md"
  cp "$repo/task.md" "$repo/after_checkbox"

  run "$PLAN_SH" "$repo/task.md" --apply
  [ "$status" -eq 3 ]

  # Nothing was touched: the file still carries the [x] and no new bullets.
  cmp "$repo/after_checkbox" "$repo/task.md"
}

@test "effort-expand-00.sh inserts one ordered bullet per task file, idempotently" {
  mkdir -p "$repo/task"
  for n in 01 02 03; do
    printf -- '- [ ] Implement task %s.\n' "$n" >"$repo/task/$n.md"
  done
  cat >"$repo/task/00.md" <<'EOF'
# Phase 0 manifest

## Subtasks

- [ ] Breakdown
- [ ] Effort — Run `skills/gubia/scripts/effort-expand-00.sh`.
- [ ] Cleanup
EOF

  run "$EXPAND_SH" "$repo/task/00.md"
  [ "$status" -eq 0 ]

  diff - "$repo/task/00.md" <<'EOF'
# Phase 0 manifest

## Subtasks

- [ ] Breakdown
- [ ] Effort — Run `skills/gubia/scripts/effort-expand-00.sh`.
- [ ] Interleave effort subtasks for `task/01.md`
- [ ] Interleave effort subtasks for `task/02.md`
- [ ] Interleave effort subtasks for `task/03.md`
- [ ] Cleanup
EOF

  cp "$repo/task/00.md" "$repo/00.before"
  run "$EXPAND_SH" "$repo/task/00.md"
  [ "$status" -eq 0 ]
  cmp "$repo/00.before" "$repo/task/00.md"
}

@test "effort-expand-00.sh reorders to numeric order and drops a stale out-of-range bullet" {
  mkdir -p "$repo/task"
  for n in 01 02 03; do
    printf -- '- [ ] Implement task %s.\n' "$n" >"$repo/task/$n.md"
  done
  # A bullet for a task file that no longer exists must not survive.
  cat >"$repo/task/00.md" <<'EOF'
# Phase 0 manifest

## Subtasks

- [ ] Breakdown
- [ ] Effort — Run `skills/gubia/scripts/effort-expand-00.sh`.
- [ ] Interleave effort subtasks for `task/99.md`
- [ ] Cleanup
EOF

  run "$EXPAND_SH" "$repo/task/00.md"
  [ "$status" -eq 0 ]

  diff - "$repo/task/00.md" <<'EOF'
# Phase 0 manifest

## Subtasks

- [ ] Breakdown
- [ ] Effort — Run `skills/gubia/scripts/effort-expand-00.sh`.
- [ ] Interleave effort subtasks for `task/01.md`
- [ ] Interleave effort subtasks for `task/02.md`
- [ ] Interleave effort subtasks for `task/03.md`
- [ ] Cleanup
EOF
}
