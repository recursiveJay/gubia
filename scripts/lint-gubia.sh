#!/usr/bin/env bash
# lint-gubia.sh — full lint harness for the repo.
#
# `just lint` uses `find -name '*.sh'`, which doesn't pick up `gubia`
# (no .sh extension). This script covers the gap documented in
# `vault/knowledge/just-lint-does-not-cover-gubia.md`: it runs `just
# lint` and also `shellcheck -x gubia` explicitly, and exits with a
# non-zero code if either one fails.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0

if ! just lint; then
    status=1
fi

if ! shellcheck -x gubia; then
    status=1
fi

exit "$status"
