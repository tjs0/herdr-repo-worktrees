#!/usr/bin/env bash
# remove.sh [workspace-id]
# Popup pane: confirm, then remove the focused worktree workspace's checkout
# and close the workspace. The branch and its commits are left intact. Herdr
# refuses if there are modified or untracked files; force with:
#   herdr worktree remove --workspace <id> --force
set -uo pipefail
here="$(dirname "$(readlink -f "$0")")"
source "$here/common.sh"
herdr="${HERDR_BIN_PATH:-herdr}"

die() {
  echo "repo-worktrees: $*" >&2
  if [ -z "${REPO_WORKTREES_NO_INTERACTIVE:-}" ]; then read -rsn1 -p "(press any key)" _; fi
  exit 1
}

ws="${1:-${HERDR_ACTIVE_WORKSPACE_ID:-$(rwt_context workspace_id)}}"
[ -n "$ws" ] || die "no workspace"
info="$("$herdr" workspace get "$ws" 2>&1)" || die "$info"
path="$(printf '%s' "$info" | jq -r 'if .result.workspace.worktree.is_linked_worktree
  then .result.workspace.worktree.checkout_path else empty end')"
[ -n "$path" ] || die "workspace $ws is not a linked git worktree"

if [ -z "${REPO_WORKTREES_NO_INTERACTIVE:-}" ]; then
  read -rn1 -p "Remove worktree '$path'? (y/n) " yn; echo
  [ "$yn" = "y" ] || exit 0
fi

out="$("$herdr" worktree remove --workspace "$ws" 2>&1)" && exit 0
code="$(printf '%s' "$out" | jq -r '.error.code // empty' 2>/dev/null)"
msg="$(printf '%s' "$out" | jq -r '.error.message // empty' 2>/dev/null)"
[ "$code" = "dirty_worktree_requires_force" ] \
  && msg="refusing: uncommitted changes. To force: herdr worktree remove --workspace $ws --force"
die "${msg:-$out}"
