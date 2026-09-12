#!/usr/bin/env bash
set -euo pipefail

# Deterministic scan of context candidates for `/gubia init`.
# Only lists; it does not read content (the selective head is done by the
# agent, capped to the first N candidates, see `init.md`).
#
# Usage: scan-init-context.sh [root-directory]
#
# Output: one line per candidate, `<category>\t<relative-path>`.
# Categories, in the priority order expected by `init.md`:
#   index   — readme/index (entry files into a tree with progressive
#             disclosure; read first to locate more pointers).
#   keyword — prd/spec/rfc/design in the name.
#   docdir  — any plain-text file under a `vault/` or `docs/` directory
#             that did not already fall into the two categories above.
#
# Restricted to plain-text extensions (.md, .txt, .rst) or no extension
# (README-style): avoids spending tokens on candidates unreadable with
# `head` (e.g. `index.html`, `spec.pdf`).

root="${1:-.}"

# Directories excluded from the traversal: not a source of product
# context and can be enormous.
excludes=(.git node_modules vendor dist build .venv target)

list_files() {
  if command -v fd >/dev/null 2>&1; then
    local exclude_args=()
    local e
    for e in "${excludes[@]}"; do
      exclude_args+=(--exclude "$e")
    done
    fd --type f --hidden "${exclude_args[@]}" . "$root"
  else
    find "$root" \
      \( -type d \( -name .git -o -name node_modules -o -name vendor \
                    -o -name dist -o -name build -o -name .venv \
                    -o -name target \) -prune \) \
      -o -type f -print
  fi
}

is_text_candidate() {
  # $1 = basename
  local base="$1" ext="${1##*.}"
  if [[ "$base" == "$ext" ]]; then
    return 0 # no extension, README-style
  fi
  case "${ext,,}" in
    md | txt | rst) return 0 ;;
    *) return 1 ;;
  esac
}

matches_any() {
  # $1 = lowercase string, rest = keywords
  local hay="$1" k
  shift
  for k in "$@"; do
    [[ "$hay" == *"$k"* ]] && return 0
  done
  return 1
}

classify() {
  # $1 = relative path
  local path="$1" base stem lower_stem
  base="$(basename "$path")"
  stem="${base%.*}"
  [[ "$stem" == "$base" ]] || : # stem already computed; no extension matches
  lower_stem="${stem,,}"

  if matches_any "$lower_stem" readme index; then
    printf 'index\t%s\n' "$path"
    return
  fi
  if matches_any "$lower_stem" prd spec rfc design; then
    printf 'keyword\t%s\n' "$path"
    return
  fi
  if [[ "$path" == */vault/* || "$path" == vault/* \
     || "$path" == */docs/* || "$path" == docs/* ]]; then
    printf 'docdir\t%s\n' "$path"
  fi
}

classified="$(
  while IFS= read -r path; do
    base="$(basename "$path")"
    is_text_candidate "$base" || continue
    classify "$path"
  done < <(list_files)
)"

# Priority order for the agent's reading cap: index first (locates more
# pointers via progressive disclosure), then keyword, then docdir.
# Alphabetical within each category, for deterministic output.
for category in index keyword docdir; do
  grep "^${category}"$'\t' <<<"$classified" | LC_ALL=C sort -t $'\t' -k2,2 || true
done
