#!/usr/bin/env bash
# Wires this checkout into the global git config. Safe to run again: it asks
# before every change, copies any file it edits first, and only ever appends.
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
config="$root/aliases.gitconfig"
gitconfig="$HOME/.gitconfig"
zshrc="$HOME/.zshrc"
source_line="source \"$root/shell/git-sb.zsh\""

# No terminal (piped into a shell, CI) means no changes that need a decision.
ask() {
	local answer
	[ -e /dev/tty ] || return 1
	printf '%s [y/N] ' "$*" >&2
	read -r answer </dev/tty || return 1
	case $answer in
		y | Y | yes | YES) return 0 ;;
		*) return 1 ;;
	esac
}

backup() {
	[ -f "$1" ] || return 0
	local copy
	copy="$1.bak.$(date +%Y%m%d%H%M%S)"
	cp "$1" "$copy"
	echo "  backup: $copy"
}

echo "Installing from $root"
echo

# --- git version ------------------------------------------------------------

read -r major minor <<<"$(git version | sed -E 's/[^0-9]*([0-9]+)\.([0-9]+).*/\1 \2/')"
if [ "$major" -lt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -lt 22 ]; }; then
	echo "warning: git $major.$minor is old, git b and git p need 2.22 for --show-current"
	echo
fi

# --- the aliases themselves -------------------------------------------------

chmod +x "$root"/bin/git-* "$root/lint.sh" "$root/hooks/pre-commit"

# Aliases written straight into ~/.gitconfig win over included ones, so sort
# that out before wiring the include up.
own=$(git config --file "$config" --name-only --get-regexp '^alias\.' | sed 's/^alias\.//' | LC_ALL=C sort)
existing=$(git config --global --show-origin --name-only --get-regexp '^alias\.' 2>/dev/null |
	awk -F'\t' -v origin="file:$gitconfig" '$1 == origin {sub(/^alias\./, "", $2); print $2}' |
	LC_ALL=C sort -u || true)
clashing=$(comm -12 <(printf '%s\n' "$own") <(printf '%s\n' "$existing") || true)

if [ -n "$clashing" ]; then
	echo 'Your ~/.gitconfig defines these aliases itself, so they would shadow the repo:'
	printf '%s\n' "$clashing" | sed 's/^/  /'
	if ask 'Remove the [alias] section from ~/.gitconfig?'; then
		backup "$gitconfig"
		git config --global --remove-section alias
		echo '  removed'
	else
		echo '  left as is, so the repo aliases stay shadowed'
	fi
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
echo

# --- the zsh side of git sb -------------------------------------------------

# git sb prints "__cd__ <path>" and the wrapper turns that into a real cd.
if [ -f "$zshrc" ] && grep -qF 'shell/git-sb.zsh' "$zshrc"; then
	echo 'zsh: already sources shell/git-sb.zsh'
elif [ -f "$zshrc" ] && grep -qF '__cd__' "$zshrc"; then
	line=$(grep -nF '__cd__' "$zshrc" | head -1 | cut -d: -f1)
	echo "zsh: ~/.zshrc has its own copy of the wrapper, around line $line."
	if ask '     Append the repo version, so the repo becomes the single source?'; then
		backup "$zshrc"
		printf '\n# git-aliases, replaces the older git() wrapper above\n%s\n' "$source_line" >>"$zshrc"
		echo '  appended, the old block is now dead code you can delete'
		echo '  pick it up with: exec zsh'
	else
		echo '  left as is'
	fi
elif ask 'zsh: let git sb change directory by sourcing it from ~/.zshrc?'; then
	backup "$zshrc"
	printf '\n# git-aliases\n%s\n' "$source_line" >>"$zshrc"
	echo '  added, pick it up with: exec zsh'
else
	echo "zsh: skipped, add this to ~/.zshrc yourself: $source_line"
fi

command -v fzf >/dev/null 2>&1 || echo 'note: git sb and git db need fzf: brew install fzf'
echo

# --- check it worked --------------------------------------------------------

git -C "$root" config core.hooksPath hooks

if git -C "$root" a >/dev/null 2>&1; then
	echo 'Done. Run: git a'
else
	echo 'Something is off: git a does not run. Check include.path in ~/.gitconfig.' >&2
	exit 1
fi
