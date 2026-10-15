#!/usr/bin/env bash
# Run every test; exit non-zero if any fails.
here="$(dirname "$(readlink -f "$0")")"
rc=0
for t in common-test.sh suggest-name-test.sh scripts-test.sh herdr-test.sh; do
  echo "== $t"
  timeout 120 "$here/$t" || { echo "FAILED: $t"; rc=1; }
done
[ "$rc" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$rc"
