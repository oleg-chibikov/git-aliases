# git-aliases

My git aliases, kept in one place so any machine can pick them up. `git a`
prints the whole list with a description for each one.

Each alias is a normal shell script in [bin/](bin), and
[aliases.gitconfig](aliases.gitconfig) is a one-line-per-alias index that points
at them.

## Install

One command:

```sh
git clone git@github.com:oleg-chibikov/git-aliases.git ~/.git-aliases && ~/.git-aliases/install.sh
```

Clone wherever you like, the path gets recorded. `install.sh` asks before every
change, copies any file it edits to `<file>.bak.<timestamp>` first, and only
ever appends to `~/.zshrc`. Answer no to everything and it changes nothing. Run
it again any time.

What it asks about:

- sets `gitaliases.dir` and `include.path` in `~/.gitconfig`
- offers to drop an existing `[alias]` section, which would shadow the repo
- offers to source [shell/git-sb.zsh](shell/git-sb.zsh) from `~/.zshrc`, which
  is what lets `git sb` change directory. If `~/.zshrc` already has its own
  `git()` wrapper it says on which line, and appending the repo version leaves
  the old block as dead code for you to delete
- points `core.hooksPath` at [hooks/](hooks) so commits here get linted
- warns if git is older than 2.22, which `git b` and `git p` need
- finishes by running `git a`, so a broken install can't pass silently

`git sb` and `git db` need fzf:

```sh
brew install fzf
```

To update later:

```sh
git -C ~/.git-aliases pull
```

No second install step, the aliases run straight from the checkout.

## Why `git sb` needs a shell function

`git sb` can switch to a branch that lives in another worktree. A git alias runs
in a subprocess and can't move the parent shell, so it prints `__cd__ <path>`
and the function in [shell/git-sb.zsh](shell/git-sb.zsh) does the `cd`. It also
moves the VS Code window, which needs the `code` CLI on PATH: VS Code palette,
"Shell Command: Install 'code'". Setting `"git.detectWorktrees": true` makes VS
Code list worktrees too.

Without the function `git sb` still works, it just prints the path instead of
going there.

## The aliases

`git a` prints this same list, read from the scripts themselves. An alias that
takes arguments explains them when you call it without any:

```
$ git cp
usage: git cp [-f] [-p] [-s] [--] <message>

  -f  push with --force-with-lease
  -p  skip the commit and push hooks
  -s  skip staging, commit whatever is staged already
  --  makes everything after it message, even if it starts with a dash
```

`-h` prints the same thing. Git puts a line about the alias above it, that's
git, not the script.

| Alias | What it does |
| --- | --- |
| `a` | List every alias with its description |
| `b` | Print the current branch name |
| `c` | Commit, args joined into the message, flags passed to `git commit`, `--` forces the rest to be message |
| `cb` | Create a branch, name normalized to lowercase-with-hyphens |
| `co` | Checkout a branch, fetch it from origin if it isn't local yet |
| `cp` | Stage all, commit, push. `-f` force-with-lease, `-p` skip hooks, `-s` skip staging, `--` forces the rest to be message |
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

The remote is `origin`, or the only remote you have if it goes by another name.
The default branch comes from `<remote>/HEAD`, falling back to `master` then
`main`. If `<remote>/HEAD` is missing, run `git remote set-head origin --auto`.

## Adding or changing an alias

1. Write `bin/git-<name>`: `#!/usr/bin/env bash`, then a `# ` comment saying
   what it does, then `set -euo pipefail`.
2. Source `bin/_lib.sh` for the shared helpers: `run` (echo a command, then run
   it), `note`, `confirm`, `die`, `require`, `default_branch`, `gone_branches`.
3. `chmod +x bin/git-<name>`.
4. Add a line to `aliases.gitconfig`, keeping the list sorted.
5. Add a row to the table above.
6. Add a check to `test.sh` if the alias does something worth pinning down.

## Checks

```sh
./lint.sh   # shape: comments, alias lines, README rows, shell style
./test.sh   # behaviour: every alias against a throwaway repo
```

`lint.sh` fails if a script has no description comment, isn't executable, misses
`set -euo pipefail`, has no alias, has no README row, or if the alias lines
drift from their fixed shape. With [shellcheck](https://www.shellcheck.net) and
[shfmt](https://github.com/mvdan/sh) installed it runs those too:

```sh
brew install shellcheck shfmt
shfmt --write --case-indent bin/* ./*.sh hooks/*
```

`test.sh` builds a repo and a `HOME` in a temp directory, so it can commit,
push and reset for real without touching anything of yours.

`install.sh` points `core.hooksPath` at [hooks/](hooks), so the lint runs before
every commit. GitHub Actions runs both on push.

## Uninstall

```sh
git config --global --unset gitaliases.dir
git config --global --unset include.path "$HOME/.git-aliases/aliases.gitconfig"
```

Then drop the `source .../shell/git-sb.zsh` line from `~/.zshrc` and delete the
checkout.

## License

[MIT](LICENSE).
