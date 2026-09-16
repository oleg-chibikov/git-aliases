# git-aliases

My git aliases, kept in one place so any machine can pick them up.

Each alias is a normal shell script in [bin/](bin), and
[aliases.gitconfig](aliases.gitconfig) is a one-line-per-alias index that points
at them.

## Install

```sh
git clone git@github.com:oleg-chibikov/git-aliases.git ~/Documents/Dev/git-aliases
cd ~/Documents/Dev/git-aliases
./install.sh
```

`install.sh` sets two things in `~/.gitconfig`: `include.path` to load the alias
list, and `gitaliases.dir` so the aliases find `bin/` wherever you cloned the
repo. If `~/.gitconfig` already defines aliases with the same names it says so
and offers to drop them, with a backup.

`git sb` and `git db` need fzf:

```sh
brew install fzf
```

## The `sb` shell function

`git sb` can switch to a branch that lives in another worktree. A git alias runs
in a subprocess and can't move the parent shell, so it prints `__cd__ <path>`
and a shell function does the `cd`. Add this to `~/.zshrc`:

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

`code -r` needs the CLI on PATH: VS Code palette, "Shell Command: Install
'code'". Setting `"git.detectWorktrees": true` makes VS Code list worktrees too.
Without the function `git sb` still works, it just prints the path instead of
going there.

## The aliases

`git a` prints this same list, read from the scripts themselves.

| Alias | What it does |
| --- | --- |
| `a` | List every alias with its description |
| `b` | Print the current branch name |
| `c` | Commit, args joined into the message, flags passed to `git commit` |
| `cb` | Create a branch, name normalized to lowercase-with-hyphens |
| `co` | Checkout a branch, fetch it from origin if it isn't local yet |
| `cp` | Stage all, commit, push. `-f` force-with-lease, `-p` skip hooks, `-s` skip staging |
| `db` | Pick local branches with fzf (TAB for several) and force-delete them |
| `dbm` | Prune remotes, then offer to delete branches whose upstream is gone |
| `dwm` | Same for worktrees: removes the worktree and its branch |
| `hr` | Hard reset to HEAD and delete untracked files |
| `last` | Show the last commit with its diff |
| `m`, `main`, `master` | Drop local changes (asks first), fetch, hard reset to the default branch |
| `p` | Pull with rebase from the matching remote branch |
| `r` | Fetch and rebase onto the default branch, `-c` uses the upstream, or pass a branch |
| `sb` | Pick a local branch with fzf and switch to it, worktrees included |
| `sr1` | Undo the last commit, keep its changes staged |
| `srmb` | Soft reset to the merge base with the default branch, keep changes staged |

The default branch comes from `origin/HEAD`, falling back to `origin/master`
then `origin/main`. If `origin/HEAD` is missing, run
`git remote set-head origin --auto`.

## Adding or changing an alias

1. Write `bin/git-<name>`: `#!/usr/bin/env bash`, then a `# ` comment saying
   what it does, then `set -euo pipefail`.
2. Source `bin/_lib.sh` for the shared helpers: `run` (echo a command, then run
   it), `note`, `confirm`, `die`, `require`, `default_branch`, `gone_branches`.
3. `chmod +x bin/git-<name>`.
4. Add a line to `aliases.gitconfig`, keeping the list sorted.
5. Add a row to the table above.

## Checks

```sh
./lint.sh
```

It fails if a script has no description comment, isn't executable, misses
`set -euo pipefail`, has no alias, has no README row, or if the alias lines
drift from their fixed shape. With [shellcheck](https://www.shellcheck.net) and
[shfmt](https://github.com/mvdan/sh) installed it runs those too:

```sh
brew install shellcheck shfmt
shfmt --write --case-indent bin/* ./*.sh hooks/*
```

`install.sh` points `core.hooksPath` at [hooks/](hooks), so the same check runs
before every commit. GitHub Actions runs it on push.
