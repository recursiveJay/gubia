#!/usr/bin/env bats

# Unit test of `run_prune_logs` (plan/task/01.md): retains the
# `loop_max_logs` most-recently-modified iteration log sets under
# `.gubia/logs/`, deleting every suffix of the pruned sets and leaving
# unrelated files untouched. Ordering is by the mtime of each set's
# `.prompt` anchor, not the numeric prefix (cross-run collision).

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  run_root="$repo"
  mkdir -p "$repo/.gubia/logs"
}

# Writes a full four-suffix set for `prefix`, then stamps the `.prompt`
# anchor with the given `mtime` (GNU `touch -d`). The suffix files keep
# their own (now) mtimes; only `.prompt` anchors the set's ordering.
make_set() {
  local prefix="$1" mtime="$2"
  : >"$repo/.gubia/logs/${prefix}.prompt"
  : >"$repo/.gubia/logs/${prefix}.out"
  : >"$repo/.gubia/logs/${prefix}.err"
  : >"$repo/.gubia/logs/${prefix}.console"
  touch -d "$mtime" "$repo/.gubia/logs/${prefix}.prompt"
}

@test "retains the loop_max_logs most-recent sets and prunes the rest atomically" {
  loop_max_logs=2
  make_set 1 '2026-09-18 10:00:00'
  make_set 2 '2026-09-18 11:00:00'
  make_set 3 '2026-09-18 12:00:00'
  make_set 4 '2026-09-18 13:00:00'

  run run_prune_logs
  [ "$status" -eq 0 ]

  # The two most recent sets (4, 3) remain with all their suffixes.
  for prefix in 4 3; do
    for suffix in prompt out err console; do
      [ -f "$repo/.gubia/logs/${prefix}.${suffix}" ]
    done
  done

  # The two oldest sets (1, 2) are gone, every suffix.
  for prefix in 1 2; do
    for suffix in prompt out err console; do
      [ ! -e "$repo/.gubia/logs/${prefix}.${suffix}" ]
    done
  done
}

@test "orders by mtime not numeric prefix: older higher-numbered set is pruned" {
  loop_max_logs=2
  # Set 1 is newest despite the lowest number; set 10 is oldest despite
  # the highest number. Numeric-prefix sorting would keep 1 and 10.
  make_set 10 '2026-09-18 09:00:00'
  make_set 2  '2026-09-18 10:00:00'
  make_set 1  '2026-09-18 11:00:00'

  run run_prune_logs
  [ "$status" -eq 0 ]

  [ -f "$repo/.gubia/logs/1.prompt" ]
  [ -f "$repo/.gubia/logs/2.prompt" ]
  for suffix in prompt out err console; do
    [ ! -e "$repo/.gubia/logs/10.${suffix}" ]
  done
}

@test "leaves unrelated non-log files untouched" {
  loop_max_logs=1
  make_set 1 '2026-09-18 10:00:00'
  make_set 2 '2026-09-18 11:00:00'
  : >"$repo/.gubia/logs/.gitkeep"
  : >"$repo/.gubia/logs/notes.txt"

  run run_prune_logs
  [ "$status" -eq 0 ]

  [ -f "$repo/.gubia/logs/.gitkeep" ]
  [ -f "$repo/.gubia/logs/notes.txt" ]
  [ -f "$repo/.gubia/logs/2.prompt" ]
  [ ! -e "$repo/.gubia/logs/1.prompt" ]
}

@test "no-op when the set count is at or below the limit" {
  loop_max_logs=3
  make_set 1 '2026-09-18 10:00:00'
  make_set 2 '2026-09-18 11:00:00'
  make_set 3 '2026-09-18 12:00:00'

  run run_prune_logs
  [ "$status" -eq 0 ]

  for prefix in 1 2 3; do
    for suffix in prompt out err console; do
      [ -f "$repo/.gubia/logs/${prefix}.${suffix}" ]
    done
  done
}

@test "no-op on a missing logs directory" {
  rm -rf "$repo/.gubia/logs"
  loop_max_logs=1
  run run_prune_logs
  [ "$status" -eq 0 ]
}
