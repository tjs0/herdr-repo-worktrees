#!/usr/bin/env bash
# open-popup.sh <new|remove>
# Plugin action command: open the matching popup pane (see herdr-plugin.toml).
set -uo pipefail
herdr="${HERDR_BIN_PATH:-herdr}"
exec "$herdr" plugin pane open --plugin "${HERDR_PLUGIN_ID:-repo-worktrees}" --entrypoint "$1"
