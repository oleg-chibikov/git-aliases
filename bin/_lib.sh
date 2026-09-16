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
	command -v "$1" >/dev/null 2>&1 || die "$1 is required, but it isn't installed"
}

# origin when it exists, otherwise the only remote there is.
default_remote() {
	local remotes
	if git remote get-url origin >/dev/null 2>&1; then
		printf 'origin\n'
		return 0
	fi
	remotes=$(git remote)
	if [ "$(printf '%s' "$remotes" | grep -c .)" = 1 ]; then
		printf '%s\n' "$remotes"
		return 0
	fi
	die 'no remote called origin, and more than one to choose from'
}

# The branch that remote points at, falling back to master then main.
default_branch() {
	local remote=$1 ref branch
	if ref=$(git symbolic-ref --quiet "refs/remotes/$remote/HEAD" 2>/dev/null); then
		printf '%s\n' "${ref#refs/remotes/"$remote"/}"
		return 0
	fi
	for branch in master main; do
		if git show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
			printf '%s\n' "$branch"
			return 0
		fi
	done
	die "no $remote/HEAD, $remote/master or $remote/main found, run: git remote set-head $remote --auto"
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
