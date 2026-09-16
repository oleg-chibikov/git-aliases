# Makes `git sb` able to change directory.
#
# `git sb` may pick a branch that lives in another worktree. A git alias runs in
# a subprocess and can't move the parent shell, so it prints "__cd__ <path>" and
# this wrapper does the cd, then points the VS Code window at the same place.
#
# install.sh offers to source this file from ~/.zshrc.

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
