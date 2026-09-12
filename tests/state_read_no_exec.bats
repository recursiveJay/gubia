#!/usr/bin/env bats

# Test of the allowlist reader (`state_read`, plan/02.md: "Never `source`
# `state.env`: read line by line with an allowlist only"): a value
# like `$(rm -rf ~)` in a key must stay literal in the exported
# variable, never get executed. `state_read` uses `printf -v`
# key by key instead of `source`, so the value never goes through
# bash command expansion.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

setup() {
  repo="$(mktemp -d)"
  cd "$repo"
  # shellcheck source=/dev/null
  source "$GUBIA_BIN"
  state_ensure
}

@test "a \$(rm -rf ~) value in state.env stays literal and does not execute" {
  # Sentinel: if `state_read` ever executed the value, this file
  # (outside the temp repo) would disappear.
  sentinel="$(mktemp)"

  sed -i "s|^fallback_list=.*|fallback_list=\$(rm -f $sentinel)|" .gubia/state.env
  state_read

  [ -f "$sentinel" ]
  [ "$fallback_list" = "\$(rm -f $sentinel)" ]

  rm -f "$sentinel"
}
