#!/usr/bin/env bash
# Unit tests for common.sh helpers.
set -uo pipefail
here="$(dirname "$(readlink -f "$0")")"
source "$here/lib.sh"
source "$here/../scripts/common.sh"
unset REPO_WORKTREES_COMMAND REPO_WORKTREES_DIR REPO_WORKTREES_PREFIX HERDR_PLUGIN_CONFIG_DIR

rwt_validate_name "good-name_1.2" 2>/dev/null; check "$?" "0" "valid name accepted"
rwt_validate_name "" 2>/dev/null;              check "$?" "1" "empty name rejected"
rwt_validate_name "-bad" 2>/dev/null;          check "$?" "1" "leading dash rejected"
rwt_validate_name ".bad" 2>/dev/null;          check "$?" "1" "leading dot rejected"
rwt_validate_name "bad/name" 2>/dev/null;      check "$?" "1" "slash rejected"
rwt_validate_name "bad name" 2>/dev/null;      check "$?" "1" "space rejected"

rwt_validate_dir ".worktrees";        check "$?" "0" "default dir accepted"
rwt_validate_dir ".claude/worktrees"; check "$?" "0" "nested dir accepted"
rwt_validate_dir "/abs";              check "$?" "1" "absolute dir rejected"
rwt_validate_dir "../out";            check "$?" "1" "parent dir rejected"
rwt_validate_dir "a/../b";            check "$?" "1" "embedded .. rejected"
rwt_validate_dir "";                  check "$?" "1" "empty dir rejected"
rwt_validate_dir "a b";               check "$?" "1" "space in dir rejected"

tmp="$(mktemp -d)"
git init -q -b main "$tmp"
git -C "$tmp" commit -q --allow-empty -m init
check "$(rwt_main_root "$tmp")" "$(git -C "$tmp" rev-parse --show-toplevel)" "main root in main repo"
git -C "$tmp" worktree add -q "$tmp/.worktrees/x" -b x main
check "$(rwt_main_root "$tmp/.worktrees/x")" "$(git -C "$tmp" rev-parse --show-toplevel)" "main root from inside worktree"
notrepo="$(mktemp -d)"
rwt_main_root "$notrepo" >/dev/null 2>&1; check "$?" "1" "non-repo path rejected"

# config: defaults, file, env override, quotes and comments
rwt_load_config
check "$RWT_COMMAND|$RWT_DIR|$RWT_PREFIX" "|.worktrees|c" "defaults"
cfg="$(mktemp -d)"
printf '# comment\ncommand = "claude --resume"\ndir=.wt\nprefix = feat-\nunknown = x\n' > "$cfg/config"
export HERDR_PLUGIN_CONFIG_DIR="$cfg"
rwt_load_config
check "$RWT_COMMAND|$RWT_DIR|$RWT_PREFIX" "claude --resume|.wt|feat-" "config file values"
REPO_WORKTREES_COMMAND="" REPO_WORKTREES_DIR=".x" rwt_load_config
check "$RWT_COMMAND|$RWT_DIR|$RWT_PREFIX" "|.x|feat-" "env overrides file, empty env clears"
printf 'command = $(touch %s/pwned)\n' "$cfg" > "$cfg/config"
rwt_load_config
[ ! -e "$cfg/pwned" ]; check "$?" "0" "config is data, not executed"

# context JSON
export HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_cwd":"/a/b","workspace_id":"w3"}'
check "$(rwt_context focused_pane_cwd)" "/a/b" "context field read"
check "$(rwt_context missing)" "" "missing context field is empty"

# info/exclude: appended once; skipped when already ignored
rwt_ensure_ignored "$tmp" ".worktrees"; rwt_ensure_ignored "$tmp" ".worktrees"
check "$(grep -c '^/.worktrees/$' "$tmp/.git/info/exclude")" "1" "exclude entry added once"
check "$(git -C "$tmp" status --porcelain)" "" "worktrees not untracked"
t2="$(mktemp -d)"; git init -q -b main "$t2"; printf '.wt/\n' > "$t2/.gitignore"
rwt_ensure_ignored "$t2" ".wt"
check "$(grep -c wt "$t2/.git/info/exclude" 2>/dev/null)" "0" "no exclude entry when already ignored"
rm -rf "$tmp" "$t2" "$notrepo" "$cfg"
exit "$fail"
