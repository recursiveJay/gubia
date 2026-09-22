#!/usr/bin/env bats

# Test of the "create evidence" subtask of plan/02.md: the creation of
# `.gubia/state.env` with its 6 keys and default values.
#
# The script under test is launched from a temporary repo (mktemp -d)
# with no prior `.gubia/state.env`; the default relative path resolves
# against the launch pwd, so `cd`-ing to the temporary repo is enough.

GUBIA_BIN="${BATS_TEST_DIRNAME}/../gubia"

@test "state.env is created with the 6 keys and their default values when it does not exist" {
  repo="$(mktemp -d)"
  cd "$repo"

  run bash "$GUBIA_BIN"
  [ "$status" -eq 0 ]

  [ -f .gubia/state.env ]

  # Exactly the 6 keys, no more, no less.
  [ "$(grep -c '=' .gubia/state.env)" -eq 6 ]
  while IFS= read -r clave; do
    grep -q "^${clave}=" .gubia/state.env
  done <<'EOF'
effort_level
fallback_list
model_index
thinking
memory_max
loop_max_logs
EOF

  # Full content against the defaults documented in
  # vault/spec/engine.md (those of the original state.toml).
  diff - .gubia/state.env <<'EOF'
effort_level=medium
fallback_list=default
model_index=0
thinking=true
memory_max=8G
loop_max_logs=20
EOF
}