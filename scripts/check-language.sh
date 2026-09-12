#!/usr/bin/env bash
# check-language.sh — one-off language gate for the translate-to-english
# migration (plan/task/09.md). Confirms mechanically that no Spanish prose
# remains in the in-scope file set. It is migration infrastructure, not a
# permanent repo contract: it is deleted with plan/ at the end.
#
# Scope (translate-to-english.md «Alcance»):
#   gubia, config/agents.sh, justfile, scripts/*.sh, skills/,
#   vault/skills/, vault/spec/, vault/conocimiento/, tests/*.bats,
#   tests/fixtures/.
#
# Excluded: .git, plan/, translate-to-english.md, tests/vendor/, and this
# script itself (its own comments and regex necessarily contain the very
# patterns it searches for).
#
# Two checks, each printed as `path:line:match`:
#   1. accented characters / ñ (unambiguous Spanish residue);
#   2. high-frequency Spanish function words (de, que, la, el, para, con,
#      una, los, las, del) matched as whole words, case-insensitive.
#
# Exits non-zero if any match is found.
set -euo pipefail

# Force a UTF-8 locale so the accented-character class matches whole
# characters, not raw bytes: under LC_ALL=C the class `[áéíóúüñ…]` is
# interpreted as a byte set and false-positives on any UTF-8 sequence
# sharing one of those bytes (e.g. `≥`/`≠`/`≤`, `¡`, emoji).
export LC_ALL=C.UTF-8
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# In-scope file set.
mapfile -t files < <(
  find \
    gubia \
    config/agents.sh \
    justfile \
    scripts \
    skills \
    vault/skills \
    vault/spec \
    vault/conocimiento \
    tests \
    -type f \
    -not -path 'tests/vendor/*' \
    -not -path 'plan/*' \
    -not -name 'translate-to-english.md' \
    -not -name 'check-language.sh' \
    | sort
)

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "check-language: no in-scope files found" >&2
  exit 1
fi

status=0

# 1. Accented characters / ñ.
accents="$(grep -HnE '[áéíóúüñÁÉÍÓÚÜÑ]' "${files[@]}" || true)"
if [[ -n "$accents" ]]; then
  printf '%s\n' "$accents"
  status=1
fi

# 2. High-frequency Spanish function words (whole words).
words="$(grep -HniE '\b(de|que|la|el|para|con|una|los|las|del)\b' "${files[@]}" || true)"
if [[ -n "$words" ]]; then
  printf '%s\n' "$words"
  status=1
fi

exit "$status"
