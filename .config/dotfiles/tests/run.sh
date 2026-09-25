#!/usr/bin/env bash
# Run every tests/test_*.sh; exit non-zero if any fails.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if ! command -v plutil >/dev/null 2>&1; then
  printf 'skipped: not macOS\n'
  exit 0
fi

rc=0
for t in test_*.sh; do
  printf '== %s\n' "${t}"
  bash "${t}" || rc=1
done
exit "${rc}"
