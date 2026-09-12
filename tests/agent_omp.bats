#!/usr/bin/env bats

# Test of agent_omp (plan/03.md): checks that the function wires up
# {prompt_file} transport (GUBIA_PROMPT_MODE) and stdout output
# (GUBIA_OUTPUT_MODE), as preserved by the agents.toml translation.

AGENTS_SH="${BATS_TEST_DIRNAME}/../config/agents.sh"

setup() {
  # shellcheck source=/dev/null
  source "$AGENTS_SH"
}

@test "agent_omp: file transport and stdout output" {
  agent_omp deepseek-v4-pro:0813 medium true /tmp/gubia-prompt.txt

  [ "$GUBIA_PROMPT_MODE" = "file" ]
  [ "$GUBIA_OUTPUT_MODE" = "stdout" ]

  # The prompt comes in via file: `-p @/tmp/gubia-prompt.txt`.
  found_prompt_file=0
  for i in "${!GUBIA_ARGV[@]}"; do
    if [ "${GUBIA_ARGV[$i]}" = "-p" ] && [ "${GUBIA_ARGV[$((i + 1))]}" = "@/tmp/gubia-prompt.txt" ]; then
      found_prompt_file=1
    fi
  done
  [ "$found_prompt_file" -eq 1 ]

  # Output does not go to a file: no -o flag in the argv.
  for arg in "${GUBIA_ARGV[@]}"; do
    [ "$arg" != "-o" ]
  done
}
