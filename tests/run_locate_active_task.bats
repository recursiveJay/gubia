#!/usr/bin/env bats

# Test of the extraction of the markdown link path from different
# forms of the first `- [ ]` of the plan (plan/04.md: "Add a
# bats-core test that verifies the extraction of the markdown link
# path from different forms of the first `- [ ]` of the plan").
#
# The `run_` module is sourced from the script (`BASH_SOURCE` guard):
# `run_locate_active_task` is called directly, without going through `main`.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
}

@test "plain link without indentation" {
  mkdir -p plan/plan
  touch plan/plan/04.md
  printf '# plan\n- [ ] [04. task](plan/04.md)\n' >plan/plan.md
  run_locate_active_task plan/plan.md
  [ "$run_active_task" = "$PWD/plan/plan/04.md" ]
}

@test "plain link with indentation before the checkbox" {
  mkdir -p plan/plan
  touch plan/plan/04.md
  printf '# plan\n  - [ ] [04. task](plan/04.md)\n' >plan/plan.md
  run_locate_active_task plan/plan.md
  [ "$run_active_task" = "$PWD/plan/plan/04.md" ]
}

@test "link between angle brackets" {
  mkdir -p "plan/plan/with space"
  touch "plan/plan/with space/04.md"
  printf '# plan\n- [ ] [04. task](<plan/with space/04.md>)\n' >plan/plan.md
  run_locate_active_task plan/plan.md
  [ "$run_active_task" = "$PWD/plan/plan/with space/04.md" ]
}

@test "link with spaces around the path" {
  mkdir -p plan/plan
  touch plan/plan/04.md
  printf '# plan\n- [ ] [04. task]( plan/04.md )\n' >plan/plan.md
  run_locate_active_task plan/plan.md
  [ "$run_active_task" = "$PWD/plan/plan/04.md" ]
}

@test "absolute link is preserved as-is" {
  mkdir -p plan
  target="$(mktemp -d)/task.md"
  touch "$target"
  printf '# plan\n- [ ] [task](%s)\n' "$target" >plan/plan.md
  run_locate_active_task plan/plan.md
  [ "$run_active_task" = "$target" ]
}

@test "first - [ ] after already-marked - [x] tasks is the one chosen" {
  mkdir -p plan/plan
  touch plan/plan/01.md plan/plan/02.md
  printf '# plan\n- [x] [01](plan/01.md)\n- [ ] [02](plan/02.md)\n' >plan/plan.md
  run_locate_active_task plan/plan.md
  [ "$run_active_task" = "$PWD/plan/plan/02.md" ]
}

@test "no - [ ] in the plan returns exit 1 without setting run_active_task" {
  mkdir -p plan
  printf '# plan\n- [x] [01](plan/01.md)\n' >plan/plan.md
  run_active_task=
  run run_locate_active_task plan/plan.md
  [ "$status" -eq 1 ]
  [ -z "$run_active_task" ]
}

@test "- [ ] without a link dies with exit 2 and its own message" {
  mkdir -p plan
  printf '# plan\n- [ ] loose task without a link\n' >plan/plan.md
  run run_locate_active_task plan/plan.md
  [ "$status" -eq 2 ]
  grep -q 'has no task file link' <<<"$output"
}
