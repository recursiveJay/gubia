#!/usr/bin/env bats

# Test of agent_codex (plan/03.md): checks that the function wires up
# stdin transport (GUBIA_PROMPT_MODE + trailing `-` in the argv) and
# file output (GUBIA_OUTPUT_MODE + `-o "$console_output"`).

AGENTS_SH="${BATS_TEST_DIRNAME}/../config/agents.sh"

setup() {
  # shellcheck source=/dev/null
  source "$AGENTS_SH"
}

@test "agent_codex: stdin transport and file output" {
  agent_codex gpt-5.6-terra medium true /tmp/console-output.txt

  [ "$GUBIA_PROMPT_MODE" = "stdin" ]
  [ "$GUBIA_OUTPUT_MODE" = "file" ]

  # The prompt comes in via stdin: the argv ends in "-".
  last_index=$(( ${#GUBIA_ARGV[@]} - 1 ))
  [ "${GUBIA_ARGV[$last_index]}" = "-" ]

  # Output goes to the given file, via -o.
  found_output_flag=0
  for i in "${!GUBIA_ARGV[@]}"; do
    if [ "${GUBIA_ARGV[$i]}" = "-o" ]; then
      found_output_flag=1
      [ "${GUBIA_ARGV[$((i + 1))]}" = "/tmp/console-output.txt" ]
    fi
  done
  [ "$found_output_flag" -eq 1 ]
}
