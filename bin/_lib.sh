#!/usr/bin/env bash
# Shared helpers for the git-* scripts next to this file. Not an alias itself.

# shellcheck disable=SC2034  # each script uses a different subset of the colours
if [ -z "${NO_COLOR:-}" ] && { [ -t 1 ] || [ -t 2 ]; }; then
	C_RESET=$'\033[0m'
	C_CMD=$'\033[1;36m'
	C_MARK=$'\033[1;33m'
	C_DIM=$'\033[38;5;240m'
	C_NOTE=$'\033[38;5;220m'
else
	C_RESET='' C_CMD='' C_MARK='' C_DIM='' C_NOTE=''
fi

# Echo a command the way a shell prompt would, then run it.
note() {
	printf '%s+%s %s%s%s\n' "$C_MARK" "$C_RESET" "$C_CMD" "$*" "$C_RESET" >&2
}

run() {
	note "$@"
	"$@"
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

# Ask on the terminal, not on stdin, so it works inside a pipeline.
confirm() {
	local answer
	printf '%s [y/N] ' "$*" >&2
	read -r answer </dev/tty || return 1
	case $answer in
		y | Y | yes | YES) return 0 ;;
		*) return 1 ;;
	esac
}

require() {
	command -v "$1" >/dev/null 2>&1 || die "$1 is required: brew install $1"
}

# The branch origin points at, falling back to master then main.
default_branch() {
	local ref branch
	if ref=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null); then
		printf '%s\n' "${ref#refs/remotes/origin/}"
		return 0
	fi
	for branch in master main; do
		if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
			printf '%s\n' "$branch"
			return 0
		fi
	done
	die 'no origin/HEAD, origin/master or origin/main found, run: git remote set-head origin --auto'
}

# The comment block under the shebang of a git-* script.
description() {
	awk 'NR == 1 {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$1"
}

# Local branches whose upstream was deleted, one per line.
gone_branches() {
	git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads/ |
		awk '/\[gone\]/ {print $1}'
}

fzf_preview='git log -n 20 --color=always --date=short --pretty=format:"%C(auto)%h %ad %an %s" {1}'
