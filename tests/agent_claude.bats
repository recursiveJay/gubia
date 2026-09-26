#!/usr/bin/env bats

# Test of agent_claude (plan/03.md): checks that the function wires up
# stdin transport (GUBIA_PROMPT_MODE) and stdout output
# (GUBIA_OUTPUT_MODE, no output file flag in the argv).

AGENTS_SH="${BATS_TEST_DIRNAME}/../config/agents.sh"

setup() {
  # shellcheck source=/dev/null
  source "$AGENTS_SH"
}

@test "agent_claude: stdin transport and stdout output" {
  agent_claude sonnet medium true

  [ "$GUBIA_PROMPT_MODE" = "stdin" ]
  [ "$GUBIA_OUTPUT_MODE" = "stdout" ]

  # The prompt comes in via stdin: `-p` with no file argument.
  found_p_flag=0
  for i in "${!GUBIA_ARGV[@]}"; do
    if [ "${GUBIA_ARGV[$i]}" = "-p" ]; then
      found_p_flag=1
    fi
  done
  [ "$found_p_flag" -eq 1 ]

  # Output does not go to a file: no -o flag in the argv.
  for arg in "${GUBIA_ARGV[@]}"; do
    [ "$arg" != "-o" ]
  done
}
