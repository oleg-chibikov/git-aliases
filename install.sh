#!/usr/bin/env bash
# Points the global git config at this checkout: gitaliases.dir for the scripts,
# include.path for the alias list. Run it once per machine, from anywhere.
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
config="$root/aliases.gitconfig"
gitconfig="$HOME/.gitconfig"

chmod +x "$root"/bin/git-* "$root/lint.sh" "$root/hooks/pre-commit"

# Aliases written straight into ~/.gitconfig win over the included ones, so deal
# with them before wiring the include up.
own=$(git config --file "$config" --name-only --get-regexp '^alias\.' | sed 's/^alias\.//' | LC_ALL=C sort)
existing=$(git config --global --show-origin --name-only --get-regexp '^alias\.' 2>/dev/null |
	awk -F'\t' -v origin="file:$gitconfig" '$1 == origin {sub(/^alias\./, "", $2); print $2}' |
	LC_ALL=C sort -u || true)
clashing=$(comm -12 <(printf '%s\n' "$own") <(printf '%s\n' "$existing") || true)

if [ -n "$clashing" ]; then
	echo 'Your ~/.gitconfig defines these aliases itself, so they would shadow the repo:'
	printf '%s\n' "$clashing" | sed 's/^/  /'
	printf 'Remove the [alias] section from ~/.gitconfig? [y/N] '
	read -r answer </dev/tty
	case $answer in
		y | Y | yes | YES)
			backup="$gitconfig.bak.$(date +%Y%m%d%H%M%S)"
			cp "$gitconfig" "$backup"
			git config --global --remove-section alias
			echo "removed, backup at $backup"
			;;
		*) echo 'left as is, the repo aliases stay shadowed' ;;
	esac
	echo
fi

git config --global gitaliases.dir "$root"
echo "gitaliases.dir = $root"

if git config --global --get-all include.path 2>/dev/null | grep -qxF "$config"; then
	echo "include.path already has $config"
else
	git config --global --add include.path "$config"
	echo "include.path += $config"
fi

command -v fzf >/dev/null 2>&1 || echo 'note: git sb and git db need fzf: brew install fzf'

# Lint on every commit in this repo.
git -C "$root" config core.hooksPath hooks

echo
echo 'Done. Run: git a'
echo 'For git sb to change directory, add the shell function from the README to ~/.zshrc.'
