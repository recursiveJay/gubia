#!/usr/bin/env bats

# Test of agent_devin (plan/03.md): checks that the function wires up
# {prompt_file} transport (GUBIA_PROMPT_MODE) and stdout output
# (GUBIA_OUTPUT_MODE).

AGENTS_SH="${BATS_TEST_DIRNAME}/../config/agents.sh"

setup() {
  # shellcheck source=/dev/null
  source "$AGENTS_SH"
}

@test "agent_devin: file transport and stdout output" {
  agent_devin swe-1.7-lightning /tmp/gubia-prompt.txt

  [ "$GUBIA_PROMPT_MODE" = "file" ]
  [ "$GUBIA_OUTPUT_MODE" = "stdout" ]

  # The prompt comes in via file: `--prompt-file /tmp/gubia-prompt.txt`.
  found_prompt_file=0
  for i in "${!GUBIA_ARGV[@]}"; do
    if [ "${GUBIA_ARGV[$i]}" = "--prompt-file" ] && [ "${GUBIA_ARGV[$((i + 1))]}" = "/tmp/gubia-prompt.txt" ]; then
      found_prompt_file=1
    fi
  done
  [ "$found_prompt_file" -eq 1 ]

  # Output does not go to a file: no -o flag in the argv.
  for arg in "${GUBIA_ARGV[@]}"; do
    [ "$arg" != "-o" ]
  done

  # Workspace-trust gate is skipped for non-interactive -p runs:
  # `--respect-workspace-trust false` (value immediately follows the flag).
  found_trust_flag=0
  for i in "${!GUBIA_ARGV[@]}"; do
    if [ "${GUBIA_ARGV[$i]}" = "--respect-workspace-trust" ] && [ "${GUBIA_ARGV[$((i + 1))]}" = "false" ]; then
      found_trust_flag=1
    fi
  done
  [ "$found_trust_flag" -eq 1 ]
}
