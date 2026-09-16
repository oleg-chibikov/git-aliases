# git-aliases

My git aliases, kept in one file so any machine can pick them up.

## Install

```sh
git clone git@github.com:oleg-chibikov/git-aliases.git ~/Documents/Dev/git-aliases
git config --global include.path ~/Documents/Dev/git-aliases/aliases.gitconfig
```

If `~/.gitconfig` already has an `[alias]` section, remove it first, otherwise
the local one wins.

Some aliases need `fzf`:

```sh
brew install fzf
```

## The `sb` wrapper

`git sb` can switch to a branch that lives in another worktree. An alias runs in
a subprocess and can't move the parent shell, so it prints `__cd__ <path>` and a
shell function does the `cd`. Add this to `~/.zshrc`:

```sh
git() {
  if [[ "$1" == "sb" ]]; then
    shift
    local out
    out=$(command git sb "$@") || return
    if [[ "$out" == "__cd__ "* ]]; then
      local dir=${out#__cd__ }
      cd "$dir" || return
      if [[ "$TERM_PROGRAM" == "vscode" ]] && (( $+commands[code] )); then
        code -r "$dir"
      fi
    fi
  else
    command git "$@"
  fi
}
```

Without it `git sb` still works, it just prints the path instead of going there.

## What's inside

Run `git a` to list everything with descriptions. Short version:

| Alias | What it does |
| --- | --- |
| `a` | List all aliases with their comments |
| `b` | Print the current branch name |
| `c` | Commit, args joined into the message, flags passed to `git commit` |
| `cb` | Create a branch, name normalized to lowercase-with-hyphens |
| `co` | Checkout a branch, fetch it from origin if it isn't local yet |
| `cp` | Stage all, commit, push. `-f` force-with-lease, `-p` no hooks, `-s` skip staging |
| `db` | Pick local branches with fzf (TAB for several) and force-delete them |
| `dbm` | Prune remotes, then offer to delete branches whose upstream is gone |
| `dwm` | Same as `dbm` for worktrees, removes the worktree and the branch |
| `hr` | Hard reset to HEAD and delete untracked files |
| `last` | Show the last commit with its diff |
| `m`, `main`, `master` | Drop local changes (asks first), fetch, hard reset to master/main |
| `p` | Pull with rebase from the matching remote branch |
| `r` | Fetch and rebase onto master/main, `-c` rebases onto `@{u}`, or pass a branch |
| `sb` | Pick a local branch with fzf and switch to it, worktrees included |
| `sr1` | Undo the last commit, keep its changes staged |
| `srmb` | Soft reset to the merge base with master/main, keep changes staged |

## Changing an alias

Edit `aliases.gitconfig`, then check it loads:

```sh
git a
```

Each alias starts with a `#` comment line. `git a` prints those, so keep them
short and accurate.
