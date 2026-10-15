#!/usr/bin/env bash
# new.sh [name]
# Popup pane: create a git worktree at <repo>/<dir>/<name> off the focused
# pane's current commit, open it as a Herdr worktree workspace grouped under
# the repo, and run the configured command in it. Prompts for the name
# (pre-filled by suggest-name.sh) unless given.
set -uo pipefail
here="$(dirname "$(readlink -f "$0")")"
source "$here/common.sh"
herdr="${HERDR_BIN_PATH:-herdr}"

die() {
  echo "repo-worktrees: $*" >&2
  if [ -z "${REPO_WORKTREES_NO_INTERACTIVE:-}" ]; then read -rsn1 -p "(press any key)" _; fi
  exit 1
}

rwt_load_config
rwt_validate_dir "$RWT_DIR" || die "invalid worktree directory: '$RWT_DIR'"

src="${HERDR_ACTIVE_PANE_CWD:-$(rwt_context focused_pane_cwd)}"
src="${src:-$PWD}"
root="$(rwt_main_root "$src")" || die "not inside a git repository: $src"

name="${1:-}"
if [ -z "$name" ]; then
  read -re -p "worktree: " -i "$("$here/suggest-name.sh" "$src")" name || exit 1
fi
rwt_validate_name "$name" 2>/dev/null || die "invalid worktree name: '$name'"

wtpath="$root/$RWT_DIR/$name"
[ -e "$wtpath" ] && die "worktree path already exists: $wtpath"
git -C "$root" show-ref --verify --quiet "refs/heads/$name" && die "branch already exists: $name"
start="$(git -C "$src" rev-parse --verify HEAD 2>/dev/null)" || die "could not resolve current commit in: $src"
rwt_ensure_ignored "$root" "$RWT_DIR" || die "could not update info/exclude for $RWT_DIR"

out="$("$herdr" worktree create --cwd "$root" --path "$wtpath" --branch "$name" \
  --base "$start" --focus 2>&1)" || die "herdr worktree create failed: $out"
if [ -n "$RWT_COMMAND" ]; then
  pane="$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id // empty')"
  [ -n "$pane" ] || die "no pane in herdr reply: $out"
  "$herdr" pane run "$pane" "$RWT_COMMAND" >/dev/null || die "could not start '$RWT_COMMAND' in $pane"
fi
