#!/usr/bin/env bash
set -euo pipefail

# Deterministic `[effort low|medium|high]` transition planner for phase 0.
# Reads a product task file (`task/NN.md`) and computes, from its first-level
# `- [ ]` subtasks, where the standalone `[effort …]` bullets must go. The
# model only turns each computed transition into a bullet; it never invents
# one.
#
# Usage: effort-plan.sh <task/NN.md> [--apply]
#
# Default (read-only) prints TSV, one transition per line:
#   <n>\t<level>\t<reason>
# where `n` counts only the first-level `- [ ]` bullets and the insertion
# point is "before bullet n". A trailing `# unmatched` section lists the
# bullets that matched no keyword (they inherit the previous level, for the
# model to review).
#
# `--apply` deletes the `[effort …]` bullets already in the file and inserts
# the recomputed ones, idempotently; it aborts without touching the file if
# any content bullet is already `[x]` (phase 0 precondition).

# --- Keyword table (single source of truth for level assignment) ----------
# Whole-word, case-insensitive, matched against the first line of each
# first-level `- [ ]` bullet. When several keywords match, the highest level
# wins (checked high → medium → low).
keywords_high=(
  judge regression unblock design architect refactor migrate investigate
  debug "root cause" concurrency race security
)
keywords_medium=(implement add fix update write create test document evidence scribe)
keywords_low=(scaffold rename move delete remove format lint bump stub commit)

# whole-word, case-insensitive match of one keyword (single word or
# space-separated phrase). $1 = lowercased haystack, $2 = keyword.
matches() {
  local hay="$1" kw="${2,,}" re
  # non-word boundary chars; a multi-word keyword's separator is one-or-more
  # non-word chars (e.g. the space in "root cause").
  re="(^|[^a-z0-9])${kw// /[^a-z0-9]+}([^a-z0-9]|$)"
  [[ "$hay" =~ $re ]]
}

# Level of one bullet's first line, plus the keyword that matched it.
# Prints `<level>\t<keyword>`; `unmatched\t-` when no keyword matches (the
# caller then inherits the previous level). The `-` placeholder keeps the
# field non-empty so `read -d` splitting never collapses it.
assign_level() {
  local line="${1,,}" kw
  for kw in "${keywords_high[@]}"; do
    matches "$line" "$kw" && { printf 'high\t%s' "$kw"; return; }
  done
  for kw in "${keywords_medium[@]}"; do
    matches "$line" "$kw" && { printf 'medium\t%s' "$kw"; return; }
  done
  for kw in "${keywords_low[@]}"; do
    matches "$line" "$kw" && { printf 'low\t%s' "$kw"; return; }
  done
  printf 'unmatched\t-'
}

# Print the first line of every first-level `- [ ]` bullet, one per line,
# skipping `[x]` bullets, indented continuation lines, and the script's own
# `[effort …]` bullets.
collect_bullets() {
  local file="$1" line text
  while IFS= read -r line; do
    [[ "$line" == "- [ ] "* ]] || continue
    text="${line#- \[ \] }"
    [[ "$text" == "[effort "* ]] && continue
    printf '%s\n' "$text"
  done < "$file"
}

# Annotate each content bullet's first line with its 0-based index and its
# assigned level+keyword. Reads `<text>` lines, prints
# `<n>\t<level>\t<keyword>\t<text>` (keyword empty when unmatched).
annotate_levels() {
  local text lvl kw n=0
  while IFS= read -r text; do
    IFS=$'\t' read -r lvl kw <<<"$(assign_level "$text")"
    printf '%d\t%s\t%s\t%s\n' "$n" "$lvl" "$kw" "$text"
    ((n += 1))
  done
}

# Resolve each bullet's level: a bullet matching no keyword (`unmatched`)
# inherits the level of the previous content bullet; the first bullet, when
# unmatched, floors to `medium` (the context-validation subtask is reading
# work, never cheap). Records the unmatched bullets as `<n>\t<text>` lines
# into `$1` for the trailing review section. Reads
# `<n>\t<level>\t<keyword>\t<text>` lines, prints the same shape with the
# level resolved.
resolve_levels() {
  local unmatched_file="$1" n level kw text prev=""
  while IFS=$'\t' read -r n level kw text; do
    if [[ "$level" == "unmatched" ]]; then
      printf '%s\t%s\n' "$n" "$text" >> "$unmatched_file"
      level="${prev:-medium}"
      kw=""
    fi
    printf '%d\t%s\t%s\t%s\n' "$n" "$level" "$kw" "$text"
    prev="$level"
  done
}

# Collapse consecutive equal levels into transitions. Reads one resolved
# `<n>\t<level>\t<keyword>\t<text>` line per first-level `- [ ]` bullet, in
# order. Prints one transition per line `<n>\t<level>\t<reason>`, where `n` is
# the 0-based content-bullet index the `[effort …]` bullet precedes. The first
# transition is always emitted, floored at `medium`; every level change emits
# the next transition (a `[judge]` raises to `high`, and the following content
# subtask restores its own level).
compute_transitions() {
  local n level kw text prev="" initial reason
  while IFS=$'\t' read -r n level kw text; do
    if [[ -z "$prev" ]]; then
      initial="$level"
      [[ "$initial" == "low" ]] && initial="medium"
      printf '%d\t%s\t%s\n' "$n" "$initial" 'initial (floor: context validation)'
    elif [[ "$level" != "$prev" ]]; then
      if [[ "$level" == "high" ]]; then
        reason='before [judge]'
      elif [[ "$prev" == "high" ]]; then
        reason="restore: next=${kw}"
      else
        reason="$kw"
      fi
      printf '%d\t%s\t%s\n' "$n" "$level" "$reason"
    fi
    prev="$level"
  done
}

# The standalone `[effort …]` bullet the model materializes, for one level.
effort_bullet() {
  local level="$1"
  printf '%s\n' "- [ ] [effort ${level}] Fix the model's capability: run \`gubia effort set ${level}\`."
}

# `--apply`: rewrite the file in place. Aborts (exit 3) without touching the
# file if any content bullet is already `[x]` (phase 0 precondition: the
# engine has not started draining it). Otherwise drops the `[effort …]`
# bullets already present and inserts the recomputed ones before the content
# bullet each transition points at, preserving every other line byte-for-byte.
apply_transitions() {
  local file="$1" transitions_file="$2" line text out content_index=0
  local -a levels=()

  # Precondition: no content bullet may be `[x]` yet.
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "- [x] "* ]]; then
      text="${line#- \[x\] }"
      [[ "$text" == "[effort "* ]] && continue
      echo "error: content bullet already [x], aborting (phase 0 precondition): $text" >&2
      exit 3
    fi
  done < "$file"

  # Transition index (0-based content-bullet position) -> level.
  while IFS=$'\t' read -r n level _; do
    levels["$n"]="$level"
  done < "$transitions_file"

  out="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "- [ ] [effort "* ]]; then
      continue
    fi
    if [[ "$line" == "- [ ] "* ]]; then
      if [[ -n "${levels[$content_index]:-}" ]]; then
        effort_bullet "${levels[$content_index]}" >> "$out"
      fi
      ((content_index += 1))
    fi
    printf '%s\n' "$line" >> "$out"
  done < "$file"

  mv "$out" "$file"
}

main() {
  local file apply=0 unmatched_file transitions_file
  if [[ $# -lt 1 ]]; then
    echo "usage: effort-plan.sh <task/NN.md> [--apply]" >&2
    exit 2
  fi
  file="$1"
  [[ $# -gt 1 && "$2" == "--apply" ]] && apply=1
  [[ -f "$file" ]] || { echo "missing file: $file" >&2; exit 1; }

  unmatched_file="$(mktemp)"
  transitions_file="$(mktemp)"

  # Pipe the content bullets through annotation, inheritance resolution, and
  # transition collapse, then print the transitions and the review list of
  # unmatched bullets (the model reviews the latter). `--apply` additionally
  # rewrites the file.
  collect_bullets "$file" \
    | annotate_levels \
    | resolve_levels "$unmatched_file" \
    | compute_transitions \
    > "$transitions_file"

  cat "$transitions_file"
  if [[ -s "$unmatched_file" ]]; then
    printf '# unmatched\n'
    cat "$unmatched_file"
  fi

  if (( apply )); then
    apply_transitions "$file" "$transitions_file"
  fi

  rm -f "$unmatched_file" "$transitions_file"
}

main "$@"
