#!/usr/bin/env bash
# End to end against a real Herdr in an isolated named session: its own HOME
# (so plugin registry, config and sockets are separate from the live server),
# a tmux client to attach the UI, and the plugin linked from this checkout.
# Opt-in: `herdr plugin link` writes the plugin registry, which Herdr keeps
# per user and which has been seen to ignore a HOME override when Herdr env
# vars leak in. Run with RWT_HERDR_E2E=1 from a shell outside Herdr only.
# Skips (exit 0) when not opted in or when herdr, tmux or jq is missing.
set -uo pipefail
here="$(dirname "$(readlink -f "$0")")"
source "$here/lib.sh"
root="$(dirname "$here")"
[ "${RWT_HERDR_E2E:-}" = 1 ] || { echo "skip: set RWT_HERDR_E2E=1 to run the Herdr end-to-end test"; exit 0; }
for c in herdr tmux jq; do command -v "$c" >/dev/null || { echo "skip: $c not found"; exit 0; }; done

# Short HOME: the session socket path must fit in sun_path.
H="$(mktemp -d /tmp/rwt.XXXXXX)"
sess="rwt-test-$$"
tm="rwt-$$"
for v in $(env | sed -n 's/^\(HERDR_[A-Za-z0-9_]*\)=.*/\1/p') TERM_PROGRAM; do unset "$v"; done
unset REPO_WORKTREES_COMMAND REPO_WORKTREES_DIR REPO_WORKTREES_PREFIX
export HOME="$H"
# A fresh HOME starts Herdr with its onboarding screen (and release notes),
# which hold the UI busy so plugin popups never open. Mark both as seen.
mkdir -p "$H/.config/herdr"
printf 'onboarding = false\n' > "$H/.config/herdr/config.toml"
printf '{"version":"%s","body":"","show_on_startup":false}\n' \
  "$(herdr --version | awk '{print $2}')" > "$H/.config/herdr/release-notes.json"
hd() { timeout 20 herdr --session "$sess" "$@"; }
cleanup() {
  hd server stop >/dev/null 2>&1
  tmux -L "$tm" kill-server >/dev/null 2>&1
  rm -rf "$H"
}
trap cleanup EXIT
screen() { tmux -L "$tm" capture-pane -p -t "$tm"; }
# diag: on a failed popup check, show what the client displayed and the
# plugin's command logs.
diag() {
  echo "--- screen:"; screen | sed '/^ *$/d'
  echo "--- plugin logs:"
  hd plugin log list --plugin repo-worktrees 2>&1 | jq -r '.result.logs[]? |
    "\(.action_id // .pane_id // "?") \(.status) exit=\(.exit_code) err=\(.stderr)"' 2>&1
}
# wait_screen <text> [secs]: poll the attached client's screen for text.
wait_screen() {
  local i
  for i in $(seq 1 $((${2:-10} * 10))); do screen | grep -qF -- "$1" && return 0; sleep 0.1; done
  return 1
}
# wait_for <secs> <cmd...>: poll until the command succeeds.
wait_for() {
  local n="$1" i; shift
  for i in $(seq 1 $((n * 10))); do "$@" >/dev/null 2>&1 && return 0; sleep 0.1; done
  return 1
}

# Isolation guard: a fresh HOME has none of the user's plugins.
[ "$(herdr plugin list --json 2>/dev/null | jq -r '.result.plugins // [] | length')" = "0" ]
check "$?" "0" "isolated HOME has an empty plugin registry"
herdr plugin link "$root" >/dev/null; check "$?" "0" "plugin links"
herdr plugin list | grep -q 'repo-worktrees'; check "$?" "0" "plugin listed"

repo="$H/repo"
git init -q -b main "$repo"
git -C "$repo" commit -q --allow-empty -m init
head="$(git -C "$repo" rev-parse HEAD)"
mkdir -p "$(herdr plugin config-dir repo-worktrees)"
printf 'command = echo RWT_RAN\nprefix = t\n' > "$(herdr plugin config-dir repo-worktrees)/config"

tmux -L "$tm" new-session -d -s "$tm" -x 150 -y 40 -c "$repo" -e HOME="$H" "herdr --session $sess"
wait_for 15 hd workspace list; check "$?" "0" "isolated session is up"

# new: popup shows the pre-filled name; Enter creates the worktree.
hd plugin action invoke repo-worktrees.new >/dev/null; check "$?" "0" "new action invokes"
wait_screen "worktree: t1"; r=$?; check "$r" "0" "popup prompts with the suggested name (prefix t)"
[ "$r" = 0 ] || diag
tmux -L "$tm" send-keys -t "$tm" Enter
wait_for 10 test -d "$repo/.worktrees/t1"; check "$?" "0" "worktree directory created in the repo"
check "$(git -C "$repo" rev-parse t1 2>/dev/null)" "$head" "branch created at the focused commit"
check "$(git -C "$repo" status --porcelain)" "" "worktree dir is not untracked"
ws="$(hd workspace list | jq -r '[.result.workspaces[] | select(.worktree.is_linked_worktree == true)][0].workspace_id // empty')"
[ -n "$ws" ]; check "$?" "0" "a linked-worktree workspace exists"
pane="$(hd pane list --workspace "$ws" | jq -r '.result.panes[0].pane_id // empty')"
wait_for 10 bash -c "herdr --session $sess pane read $pane --source recent 2>/dev/null | grep -q RWT_RAN"
check "$?" "0" "configured command ran in the new pane"

# remove: refuses with a dirty tree, keeps everything.
touch "$repo/.worktrees/t1/dirty"
hd plugin action invoke repo-worktrees.remove >/dev/null
wait_screen "Remove worktree"; r=$?; check "$r" "0" "remove popup asks for confirmation"
[ "$r" = 0 ] || diag
tmux -L "$tm" send-keys -t "$tm" y
wait_screen "uncommitted changes"; check "$?" "0" "dirty worktree is refused with a hint"
tmux -L "$tm" send-keys -t "$tm" x
test -d "$repo/.worktrees/t1"; check "$?" "0" "dirty worktree kept"

# remove: clean tree is removed, branch stays.
rm "$repo/.worktrees/t1/dirty"
hd plugin action invoke repo-worktrees.remove >/dev/null
wait_screen "Remove worktree"
tmux -L "$tm" send-keys -t "$tm" y
wait_for 10 test ! -d "$repo/.worktrees/t1"; check "$?" "0" "clean worktree directory removed"
git -C "$repo" rev-parse --verify -q t1 >/dev/null; check "$?" "0" "branch kept after removal"

# new: an invalid name reports the error in the popup and waits for a key.
hd plugin action invoke repo-worktrees.new >/dev/null
wait_screen "worktree: t1"
tmux -L "$tm" send-keys -t "$tm" C-u
tmux -L "$tm" send-keys -t "$tm" -l "bad name"
tmux -L "$tm" send-keys -t "$tm" Enter
wait_screen "invalid worktree name"; check "$?" "0" "invalid name error shown in the popup"
wait_screen "press any key"; check "$?" "0" "popup waits for a key"
tmux -L "$tm" send-keys -t "$tm" x
wait_for 5 bash -c "! tmux -L $tm capture-pane -p -t $tm | grep -q 'press any key'"
check "$?" "0" "popup closes after the key"

exit "$fail"
