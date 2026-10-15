#!/usr/bin/env bash
# new.sh / remove.sh against a stub herdr CLI (never a real server).
set -uo pipefail
here="$(dirname "$(readlink -f "$0")")"
source "$here/lib.sh"
bin="$here/../scripts"
unset REPO_WORKTREES_COMMAND REPO_WORKTREES_DIR REPO_WORKTREES_PREFIX HERDR_PLUGIN_CONFIG_DIR HERDR_ACTIVE_PANE_CWD HERDR_ACTIVE_WORKSPACE_ID HERDR_PLUGIN_CONTEXT_JSON

# Stub herdr: logs argv, answers worktree create / workspace get / worktree remove.
stubdir="$(mktemp -d)"
log="$stubdir/log"
cat > "$stubdir/herdr" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
case "\$1 \$2" in
  "worktree create") echo '{"result":{"root_pane":{"pane_id":"w9:p1"}}}' ;;
  "workspace get")
    if [ "\$3" = "wlinked" ]; then
      echo '{"result":{"workspace":{"worktree":{"is_linked_worktree":true,"checkout_path":"/r/.worktrees/x"}}}}'
    else
      echo '{"result":{"workspace":{}}}'
    fi ;;
  "worktree remove")
    if [ -n "\${STUB_DIRTY:-}" ]; then
      echo '{"error":{"code":"dirty_worktree_requires_force","message":"dirty"}}'; exit 1
    fi
    echo '{"result":{"type":"worktree_removed"}}' ;;
esac
STUB
chmod +x "$stubdir/herdr"
export HERDR_BIN_PATH="$stubdir/herdr" REPO_WORKTREES_NO_INTERACTIVE=1

tmp="$(mktemp -d)"
git init -q -b main "$tmp"
git -C "$tmp" commit -q --allow-empty -m init
head="$(git -C "$tmp" rev-parse HEAD)"

# new: repo-local path, branch, base at current commit; no command by default.
: > "$log"
HERDR_ACTIVE_PANE_CWD="$tmp" "$bin/new.sh" feat >/dev/null 2>&1; check "$?" "0" "new exits 0"
check "$(sed -n 1p "$log")" \
  "worktree create --cwd $tmp --path $tmp/.worktrees/feat --branch feat --base $head --focus" \
  "new creates repo-local worktree off HEAD"
check "$(wc -l < "$log")" "1" "no command configured: nothing run in the pane"
check "$(git -C "$tmp" status --porcelain)" "" "worktree dir excluded from status"

# new: the source dir comes from the plugin context when no env override.
: > "$log"
HERDR_PLUGIN_CONTEXT_JSON="{\"focused_pane_cwd\":\"$tmp\"}" "$bin/new.sh" viactx >/dev/null 2>&1
check "$(sed -n 1p "$log" | cut -d' ' -f3-6)" "--cwd $tmp --path $tmp/.worktrees/viactx" "new reads focused_pane_cwd from the context"

# new: configured command, dir and prefix.
: > "$log"
HERDR_ACTIVE_PANE_CWD="$tmp" REPO_WORKTREES_COMMAND="claude --x" REPO_WORKTREES_DIR=.wt "$bin/new.sh" cmd >/dev/null 2>&1
check "$(sed -n 1p "$log" | cut -d' ' -f3-6)" "--cwd $tmp --path $tmp/.wt/cmd" "new honors the configured dir"
check "$(sed -n 2p "$log")" "pane run w9:p1 claude --x" "new runs the configured command in the new pane"

# new from inside a linked worktree still roots at the main tree.
git -C "$tmp" worktree add -q "$tmp/.worktrees/inner" -b inner
: > "$log"
HERDR_ACTIVE_PANE_CWD="$tmp/.worktrees/inner" "$bin/new.sh" feat2 >/dev/null 2>&1
check "$(sed -n 1p "$log" | cut -d' ' -f3-6)" "--cwd $tmp --path $tmp/.worktrees/feat2" "new from a worktree uses the main root"

# new refuses: bad name, existing branch, not a repo, bad dir. Herdr never called.
: > "$log"
HERDR_ACTIVE_PANE_CWD="$tmp" "$bin/new.sh" "bad name" >/dev/null 2>&1; check "$?" "1" "invalid name exits 1"
HERDR_ACTIVE_PANE_CWD="$tmp" "$bin/new.sh" inner >/dev/null 2>&1; check "$?" "1" "existing branch exits 1"
HERDR_ACTIVE_PANE_CWD="$tmp" REPO_WORKTREES_DIR=../out "$bin/new.sh" q >/dev/null 2>&1; check "$?" "1" "bad dir exits 1"
notrepo="$(mktemp -d)"
HERDR_ACTIVE_PANE_CWD="$notrepo" "$bin/new.sh" x >/dev/null 2>&1; check "$?" "1" "not a repo exits 1"
check "$(wc -l < "$log")" "0" "refusals never call herdr"

# remove: removes a linked worktree workspace.
: > "$log"
"$bin/remove.sh" wlinked >/dev/null 2>&1; check "$?" "0" "remove exits 0"
check "$(sed -n 2p "$log")" "worktree remove --workspace wlinked" "remove runs without --force"

# remove: workspace id from the plugin context.
: > "$log"
HERDR_PLUGIN_CONTEXT_JSON='{"workspace_id":"wlinked"}' "$bin/remove.sh" >/dev/null 2>&1
check "$(sed -n 2p "$log")" "worktree remove --workspace wlinked" "remove reads workspace_id from the context"

# remove: refuses a non-worktree workspace without calling remove.
: > "$log"
"$bin/remove.sh" wplain >/dev/null 2>&1; check "$?" "1" "non-worktree exits 1"
check "$(grep -c 'worktree remove' "$log")" "0" "non-worktree never removed"

# remove: dirty -> exit 1 with the force hint.
out="$(STUB_DIRTY=1 "$bin/remove.sh" wlinked 2>&1)"; check "$?" "1" "dirty exits 1"
case "$out" in *"--workspace wlinked --force"*) echo "ok: dirty prints force hint";; *) echo "FAIL: dirty force hint (got: $out)"; fail=1;; esac

rm -rf "$stubdir" "$tmp" "$notrepo"
exit "$fail"
