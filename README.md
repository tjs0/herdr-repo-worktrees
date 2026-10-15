# herdr-repo-worktrees

A [Herdr](https://herdr.dev) plugin that keeps git worktrees inside the repo,
at `<repo>/.worktrees/<name>`, opens each as a Herdr worktree workspace grouped
under the repo, and removes them again.

Herdr's own worktree creation puts every checkout under one global
`[worktrees] directory`. A per-repo location was requested in
[herdrdev/herdr#261](https://github.com/herdrdev/herdr/issues/261) and closed as
not planned. This plugin passes an explicit `--path` to `herdr worktree create`
instead. It needs only bash, git, jq, and Herdr.

Compared with [herdr-worktrunk](https://github.com/devashish2203/herdr-worktrunk),
which delegates to the worktrunk tool, this has no dependency beyond git and jq
and a fixed in-repo layout.

## Requirements

- Herdr 0.9.5 or newer
- bash, git, jq
- Linux or macOS

## Install

```sh
herdr plugin install tjs0/herdr-repo-worktrees
```

## Keybindings

In `~/.config/herdr/config.toml`. Unbind the built-in `new_worktree`, which
would still create checkouts under the global directory:

```toml
[keys]
new_worktree = ""

[[keys.command]]
key = "prefix+f"
type = "plugin_action"
command = "repo-worktrees.new"
description = "new worktree"

[[keys.command]]
key = "prefix+shift+f"
type = "plugin_action"
command = "repo-worktrees.remove"
description = "remove worktree"
```

Each action opens a popup (a plugin pane with `placement = "popup"`). The popup
takes its repo from the focused pane's working directory, so it works from the
main checkout or from any linked worktree.

## Creating

The popup asks for a name, pre-filled with the first unused `<prefix><N>`
(`c1`, `c2`, ...). Names may contain letters, digits, `.`, `_`, `-` and may not
start with `-` or `.`. The branch has the same name, created at the focused
pane's current commit. The checkout goes to `<repo>/<dir>/<name>`, where
`<repo>` is the main working tree even when you start from a linked worktree.

A name, branch, or path that already exists is refused. Any error is printed in
the popup, which waits for a key.

If `<dir>` is not already git-ignored, `/<dir>/` is appended to the repo's
`info/exclude` (under `git rev-parse --git-common-dir`), so worktrees never
show as untracked. Nothing tracked is edited.

## Removing

The popup confirms with `y`/`n`, then runs `herdr worktree remove` for the
focused workspace, which removes the checkout and closes the workspace. The
branch and its commits stay. Git refuses when there are modified or untracked
files; the popup says so and prints the forcing command:

```sh
herdr worktree remove --workspace <id> --force
```

A workspace that is not a linked worktree is refused.

## Configuration

Optional file `config` in the plugin config directory
(`herdr plugin config-dir repo-worktrees`), one `key = value` per line, `#` for
comments. It is read as data, never executed.

| Key | Default | Meaning |
| --- | --- | --- |
| `command` | none | Run in the new worktree's pane, for example `claude`. Empty leaves a plain shell. |
| `dir` | `.worktrees` | Worktree directory relative to the repo root. Letters, digits, `.`, `_`, `-`, with `/` for nesting; no `..`. |
| `prefix` | `c` | Prefix of the suggested name (`c1`, `c2`, ...). |

The environment variables `REPO_WORKTREES_COMMAND`, `REPO_WORKTREES_DIR` and
`REPO_WORKTREES_PREFIX` override the file when set (an empty value counts as
set).

## Tests

```sh
tests/run.sh
```

Unit tests and tests against a stub `herdr` always run. `tests/herdr-test.sh`
drives a real Herdr through tmux in an isolated session and HOME. It links the
plugin, which writes Herdr's per-user plugin registry, so it only runs with
`RWT_HERDR_E2E=1` from a shell outside Herdr.

## License

MIT
