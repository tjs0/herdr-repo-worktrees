#!/usr/bin/env bash
set -uo pipefail
here="$(dirname "$(readlink -f "$0")")"
source "$here/lib.sh"
bin="$here/../scripts/suggest-name.sh"
unset REPO_WORKTREES_COMMAND REPO_WORKTREES_DIR REPO_WORKTREES_PREFIX HERDR_PLUGIN_CONFIG_DIR

tmp="$(mktemp -d)"
git init -q -b main "$tmp"
git -C "$tmp" commit -q --allow-empty -m init

check "$("$bin" "$tmp")" "c1" "first suggestion is c1"
git -C "$tmp" worktree add -q "$tmp/.worktrees/c1" -b c1 main
check "$("$bin" "$tmp")" "c2" "skips existing c1"

notrepo="$(mktemp -d)"
check "$("$bin" "$notrepo")" "c1" "fallback outside repo"

tmp2="$(mktemp -d)"
git init -q -b main "$tmp2"
git -C "$tmp2" commit -q --allow-empty -m init
git -C "$tmp2" branch c1
check "$("$bin" "$tmp2")" "c2" "skips lingering branch c1"

# prefix and dir come from the settings
git -C "$tmp" worktree add -q "$tmp/.worktrees/feat-1" -b feat-1 main
check "$(REPO_WORKTREES_PREFIX=feat- "$bin" "$tmp")" "feat-2" "custom prefix"
mkdir -p "$tmp/.wt/z-1"
check "$(REPO_WORKTREES_PREFIX=z- REPO_WORKTREES_DIR=.wt "$bin" "$tmp")" "z-2" "custom dir is checked"

rm -rf "$tmp" "$tmp2" "$notrepo"
exit "$fail"
