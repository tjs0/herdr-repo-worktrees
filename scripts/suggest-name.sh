#!/usr/bin/env bash
# suggest-name.sh [dir]: print the first unused <prefix><N> (c1, c2, ...) for
# the repo containing dir, skipping existing worktree directories and branches.
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/common.sh"
rwt_load_config

src="${1:-$PWD}"
if root="$(rwt_main_root "$src")"; then
  n=1
  while [ -e "$root/$RWT_DIR/$RWT_PREFIX$n" ] \
     || git -C "$root" show-ref --verify --quiet "refs/heads/$RWT_PREFIX$n"; do
    n=$((n + 1))
  done
  printf '%s%s\n' "$RWT_PREFIX" "$n"
else
  printf '%s1\n' "$RWT_PREFIX"
fi
