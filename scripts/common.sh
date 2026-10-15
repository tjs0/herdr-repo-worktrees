# Shared helpers for the repo-worktrees scripts. Sourced, not executed.

# Print absolute path to the MAIN working tree of the repo containing $1,
# even when $1 is itself a linked worktree. Returns non-zero if not a repo.
rwt_main_root() {
  local src="$1" common
  common="$(git -C "$src" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  dirname "$common"
}

# Validate a worktree/branch name. Allowed: [A-Za-z0-9._-], not empty,
# not starting with '-' or '.'. Prints reason to stderr and returns 1 on failure.
rwt_validate_name() {
  local name="$1"
  if [ -z "$name" ]; then
    echo "error: worktree name must not be empty" >&2
    return 1
  fi
  case "$name" in
    -*|.*)
      echo "error: worktree name must not start with '-' or '.': $name" >&2
      return 1 ;;
  esac
  if ! printf '%s' "$name" | grep -qE '^[A-Za-z0-9._-]+$'; then
    echo "error: name may only contain letters, digits, '.', '_', '-': $name" >&2
    return 1
  fi
  return 0
}

# Validate the worktree directory: a relative path of [A-Za-z0-9._-]
# components, no '..'. Returns 1 on failure.
rwt_validate_dir() {
  local dir="$1"
  printf '%s' "$dir" | grep -qE '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$' || return 1
  case "/$dir/" in */../*) return 1 ;; esac
  return 0
}

# Load settings into RWT_COMMAND, RWT_DIR, RWT_PREFIX. Precedence: the
# REPO_WORKTREES_{COMMAND,DIR,PREFIX} env vars, then `key = value` lines in
# $HERDR_PLUGIN_CONFIG_DIR/config (read as data, never executed), then defaults.
rwt_load_config() {
  RWT_COMMAND="" RWT_DIR=".worktrees" RWT_PREFIX="c"
  local file="${HERDR_PLUGIN_CONFIG_DIR:-}/config" key val
  if [ -n "${HERDR_PLUGIN_CONFIG_DIR:-}" ] && [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in ''|'#'*) continue ;; esac
      key="${line%%=*}"; val="${line#*=}"
      key="$(printf '%s' "$key" | tr -d '[:space:]')"
      val="$(printf '%s' "$val" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^"(.*)"$/\1/')"
      case "$key" in
        command) RWT_COMMAND="$val" ;;
        dir) RWT_DIR="$val" ;;
        prefix) RWT_PREFIX="$val" ;;
      esac
    done < "$file"
  fi
  RWT_COMMAND="${REPO_WORKTREES_COMMAND-$RWT_COMMAND}"
  RWT_DIR="${REPO_WORKTREES_DIR-$RWT_DIR}"
  RWT_PREFIX="${REPO_WORKTREES_PREFIX-$RWT_PREFIX}"
}

# Print a field of the focused context, from HERDR_PLUGIN_CONTEXT_JSON.
rwt_context() {
  [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ] || return 0
  printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null
}

# Make sure <dir> is ignored in the repo at $1 (main root): if git does not
# already ignore it, append "/<dir>/" to info/exclude under the common git dir.
rwt_ensure_ignored() {
  local root="$1" dir="$2" common
  git -C "$root" check-ignore -q "$dir/x" 2>/dev/null && return 0
  common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)" || return 1
  mkdir -p "$common/info" || return 1
  printf '/%s/\n' "$dir" >> "$common/info/exclude"
}
