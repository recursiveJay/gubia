#!/usr/bin/env bash
set -euo pipefail

# Deterministic `[effort …]` bullet expansion for the phase-0 manifest
# (`task/00.md`). Appends, immediately after the Effort subtask, one
# "Interleave effort subtasks for `task/NN.md`" bullet per product task file
# `task/01.md`..`task/NN.md` in numeric order, so the per-file effort work is
# drained serially, one iteration each.
#
# Usage: effort-expand-00.sh [task/00.md]
#
# Idempotent: it drops any "Interleave effort subtasks …" bullets already in
# the file and re-emits the full ordered set, so running it twice changes
# nothing (and a file added later lands in its numeric position, not out of
# order). It does not process any task file and does not mark anything.

manifest="${1:-task/00.md}"

if [[ ! -f "$manifest" ]]; then
  echo "missing manifest: $manifest" >&2
  exit 1
fi

task_dir="$(dirname "$manifest")"

# Product task files `01.md`..`99.md` in numeric order, excluding `00.md`.
# The glob's own sort is not relied upon: names are sorted explicitly.
files=()
for f in "$task_dir"/[0-9][0-9].md; do
  [[ -e "$f" ]] || continue
  base="${f##*/}"
  [[ "$base" == "00.md" ]] && continue
  files+=("$base")
done
if (( ${#files[@]} > 0 )); then
  mapfile -t files < <(printf '%s\n' "${files[@]}" | LC_ALL=C sort)
fi

# True for the bullets this script owns, in either checkbox state.
is_expand_bullet() {
  local b="$1"
  [[ "$b" == "- [ ] Interleave effort subtasks for \`task/"*".md\`" ]] ||
    [[ "$b" == "- [x] Interleave effort subtasks for \`task/"*".md\`" ]]
}

effort_seen=0
tmp_file="$(mktemp)"
while IFS= read -r line; do
  # Drop bullets this script owns: they are re-emitted in order below.
  if is_expand_bullet "$line"; then
    continue
  fi
  printf '%s\n' "$line" >> "$tmp_file"
  if (( ! effort_seen )) && [[ "$line" == "- [ ] Effort "* || "$line" == "- [x] Effort "* ]]; then
    effort_seen=1
    for base in "${files[@]}"; do
      nn="${base%.md}"
      printf '%s\n' "- [ ] Interleave effort subtasks for \`task/${nn}.md\`" >> "$tmp_file"
    done
  fi
done < "$manifest"

if (( ! effort_seen )); then
  echo "no Effort subtask found in $manifest" >&2
  rm -f "$tmp_file"
  exit 1
fi

mv "$tmp_file" "$manifest"
