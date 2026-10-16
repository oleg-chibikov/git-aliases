#!/usr/bin/env bash
# Runs the aliases against a throwaway repo, with a throwaway HOME, and checks
# what they did. Touches nothing outside its temp directory.
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
tmp=$(cd "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

checks=0
failures=0

pass() { checks=$((checks + 1)); }

fail() {
	checks=$((checks + 1))
	failures=$((failures + 1))
	printf 'FAIL %s\n' "$1" >&2
	printf '  expected: %s\n' "$2" >&2
	printf '  actual:   %s\n' "$3" >&2
}

is() {
	if [ "$2" = "$3" ]; then pass; else fail "$1" "$2" "$3"; fi
}

has() {
	case $3 in
		*"$2"*) pass ;;
		*) fail "$1" "output containing '$2'" "$3" ;;
	esac
}

# Checks a command exits non-zero and says why.
refuses() {
	local label=$1 fragment=$2
	shift 2
	local output exit_code=0
	output=$("$@" 2>&1) || exit_code=$?
	if [ "$exit_code" -eq 0 ]; then
		fail "$label" 'a non-zero exit' 'exit 0'
	else
		has "$label" "$fragment" "$output"
	fi
}

# --- a git that only knows these aliases ------------------------------------

export HOME="$tmp/home"
export NO_COLOR=1
unset XDG_CONFIG_HOME
mkdir -p "$HOME"

git config --global gitaliases.dir "$root"
git config --global include.path "$root/aliases.gitconfig"
git config --global user.name 'Test User'
git config --global user.email 'test@example.com'
git config --global commit.gpgsign false
git config --global init.defaultBranch main

git init -q --bare "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/work" 2>/dev/null
cd "$tmp/work"

echo one >file.txt
git add -A
git commit -qm 'init'
git push -q -u origin main
git remote set-head origin --auto >/dev/null

# --- the aliases ------------------------------------------------------------

is 'git b prints the branch' main "$(git b)"

git cb 'Feature X!' >/dev/null 2>&1
is 'git cb normalizes the name' feature-x "$(git b)"

refuses 'git c without a message' 'usage: git c' git c

for alias_name in c cb co cp r; do
	refuses "git $alias_name -h shows the usage" "usage: git $alias_name" git "$alias_name" -h
done

for alias_name in cb co cp; do
	refuses "git $alias_name without arguments shows the usage" "usage: git $alias_name" git "$alias_name"
done

has 'the usage explains the flags' '-f  push with --force-with-lease' "$(git cp -h 2>&1 || true)"

echo two >>file.txt
git add -A
git c fixed the file >/dev/null 2>&1
is 'git c joins the message' 'fixed the file' "$(git log -1 --format=%s)"

echo three >>file.txt
git add -A
git c -- -fixed with a dash >/dev/null 2>&1
is 'git c takes a message starting with a dash after --' '-fixed with a dash' "$(git log -1 --format=%s)"
git reset -q --soft HEAD~1

has 'git last shows the commit' 'fixed the file' "$(git last)"

git sr1 >/dev/null 2>&1
is 'git sr1 drops the commit' 'init' "$(git log -1 --format=%s)"
is 'git sr1 keeps the change staged' 'file.txt' "$(git diff --cached --name-only)"

git cp -s second commit >/dev/null 2>&1
is 'git cp commits' 'second commit' "$(git log -1 --format=%s)"
is 'git cp pushes' 'second commit' "$(git -C "$tmp/origin.git" log -1 --format=%s feature-x)"

echo junk >junk.txt
git hr >/dev/null 2>&1
if [ -e junk.txt ]; then
	fail 'git hr deletes untracked files' 'junk.txt gone' 'junk.txt still there'
else
	pass
fi

git srmb >/dev/null 2>&1
is 'git srmb resets to the merge base' "$(git rev-parse origin/main)" "$(git rev-parse HEAD)"

git reset -q --hard
git master >/dev/null 2>&1
is 'git master switches to the default branch' main "$(git b)"

git co feature-x >/dev/null 2>&1
is 'git co switches to a local branch' feature-x "$(git b)"

git clone -q "$tmp/origin.git" "$tmp/elsewhere"
git -C "$tmp/elsewhere" checkout -q -b remote-only
git -C "$tmp/elsewhere" commit -q --allow-empty -m 'made elsewhere'
git -C "$tmp/elsewhere" push -q -u origin remote-only

git co remote-only >/dev/null 2>&1
is 'git co fetches a branch it does not have' remote-only "$(git b)"

git checkout -q main
git r >/dev/null 2>&1
is 'git r leaves an up to date branch alone' "$(git rev-parse origin/main)" "$(git rev-parse HEAD)"

git p >/dev/null 2>&1
is 'git p leaves an up to date branch alone' "$(git rev-parse origin/main)" "$(git rev-parse HEAD)"

has 'git dbm finds nothing to delete' 'No deletable branches or worktrees with a gone upstream.' "$(git dbm 2>&1)"

# --- branch and worktree deletion -------------------------------------------

# shellcheck source=bin/_lib.sh
. "$root/bin/_lib.sh"

confirm() {
	printf '%s\n' "$*" >>"$tmp/confirmations"
	[ "${delete_answer:-no}" = yes ]
}

fzf() {
	local input
	input=$(cat)
	printf '%s\n' "$input" >"$tmp/picker"
	printf '%s\n' "$input" | awk -F'\t' 'index("\n" ENVIRON["pick_branch"] "\n", "\n" $1 "\n")'
}
export -f fzf
export tmp

git branch delete-plain
git worktree add -q -b delete-clean "$tmp/clean worktree"
git worktree add -q -b delete-dirty "$tmp/dirty"
git worktree add -q -b delete-locked "$tmp/locked"
git worktree lock "$tmp/locked"
git worktree add -q --detach "$tmp/detached"
git worktree add -q -b delete-missing "$tmp/missing"
git worktree add -q -b delete-odd "$tmp/odd"$'\t\n'"path"
git config branch.delete-clean.description 'private branch setting'
clean_gitdir=$(git -C "$tmp/clean worktree" rev-parse --absolute-git-dir)
echo dirty >>"$tmp/dirty/file.txt"
echo untracked >"$tmp/dirty/untracked.txt"
echo ignored >"$tmp/dirty/ignored.cache"
echo '*.cache' >>.git/info/exclude
echo ignored >"$tmp/clean worktree/ignored.cache"
echo shared-stash >>file.txt
git stash push -qm shared-stash
shared_stash=$(git rev-parse refs/stash)

load_deletion_worktrees
candidates=$(deletion_candidates all)
has 'picker labels branches' $'delete-plain\tbranch\t[branch]' "$candidates"
has 'picker labels worktrees and paths' "[worktree] $tmp/clean worktree" "$candidates"
has 'picker includes detached worktrees' '[worktree detached]' "$candidates"
is 'picker excludes locked worktrees' '' "$(printf '%s\n' "$candidates" | grep -F delete-locked || true)"
is 'picker excludes current branch' '' "$(printf '%s\n' "$candidates" | awk -F'\t' '$1 == "main"')"
linked_candidates=$(cd "$tmp/dirty" && load_deletion_worktrees && deletion_candidates all)
is 'picker excludes the main worktree from a linked worktree' '' "$(printf '%s\n' "$linked_candidates" | awk -F'\t' '$1 == "main"')"
is 'picker excludes the current linked worktree' '' "$(printf '%s\n' "$linked_candidates" | grep -F delete-dirty || true)"
detached_candidates=$(cd "$tmp/detached" && load_deletion_worktrees && deletion_candidates all)
is 'picker excludes the current detached worktree' '' "$(printf '%s\n' "$detached_candidates" | grep -F '[worktree detached]' || true)"

export pick_branch=$'delete-clean\ndelete-plain'
git db >"$tmp/delete-output" 2>&1
is 'git db removes the worktree folder' no "$([ -e "$tmp/clean worktree" ] && echo yes || echo no)"
is 'git db removes private metadata' no "$([ -e "$clean_gitdir" ] && echo yes || echo no)"
is 'git db removes branch refs' '' "$(git branch --list delete-clean)"
is 'git db removes branch configuration' '' "$(git config --get branch.delete-clean.description || true)"
is 'git db removes branch reflog' no "$(git reflog exists refs/heads/delete-clean && echo yes || echo no)"
has 'git db passes labeled entries to fzf' '[branch]' "$(<"$tmp/picker")"
is 'git db multi-select also deletes a plain branch' '' "$(git branch --list delete-plain)"

load_deletion_worktrees
selected=$(deletion_candidates all | awk -F'\t' '$1 == "delete-dirty"')
# shellcheck disable=SC2016
refuses 'dirty worktree requires confirmation' 'worktree retained:' bash -c '
	. "$1/bin/_lib.sh"
	confirm() { return 1; }
	load_deletion_worktrees
	delete_candidates "$2"
' bash "$root" "$selected"
is 'declining keeps dirty files' dirty "$(tail -n 1 "$tmp/dirty/file.txt")"
has 'declining keeps branch' 'delete-dirty' "$(git branch --list delete-dirty)"
delete_answer=yes
delete_candidates "$selected" >"$tmp/delete-output" 2>&1
has 'forced removal warns about data loss' 'including uncommitted and untracked files?' "$(<"$tmp/confirmations")"
is 'forced removal deletes the folder and ignored files' no "$([ -e "$tmp/dirty" ] && echo yes || echo no)"
is 'forced removal deletes the branch' '' "$(git branch --list delete-dirty)"

# git drops the registration, then fails because a dev server wrote a new file.
git() {
	local last
	for last; do :; done
	if [ "${1:-} ${2:-}" = 'worktree remove' ] && [ "$last" = "${busy_path:-}" ]; then
		command git "$@" || return
		mkdir -p "$last/.vite"
		echo "error: failed to delete '$last': Directory not empty" >&2
		return 1
	fi
	command git "$@"
}
git worktree add -q -b delete-busy-clean "$tmp/busy-clean"
busy_path="$tmp/busy-clean"
: >"$tmp/confirmations"
delete_answer=no
load_deletion_worktrees
selected=$(deletion_candidates all | awk -F'\t' '$1 == "delete-busy-clean"')
delete_candidates "$selected" >"$tmp/delete-output" 2>&1
is 'a clean folder refilled during removal is deleted without asking' '' "$(<"$tmp/confirmations")"
is 'a clean folder refilled during removal is deleted' no "$([ -e "$tmp/busy-clean" ] && echo yes || echo no)"
is 'a clean folder refilled during removal loses its branch' '' "$(git branch --list delete-busy-clean)"

git worktree add -q -b delete-busy "$tmp/busy"
git worktree add -q -b delete-after-busy "$tmp/after-busy"
echo untracked >"$tmp/busy/untracked.txt"
busy_path="$tmp/busy"
delete_answer=yes
load_deletion_worktrees
selected=$(deletion_candidates all | awk -F'\t' '$1 == "delete-busy" || $1 == "delete-after-busy"')
delete_candidates "$selected" >"$tmp/delete-output" 2>&1
is 'a dirty folder refilled during removal is deleted' no "$([ -e "$tmp/busy" ] && echo yes || echo no)"
is 'a dirty folder refilled during removal loses its branch' '' "$(git branch --list delete-busy)"
is 'deletion continues after a refilled folder' '' "$(git branch --list delete-after-busy)"

git worktree add -q -b delete-stuck "$tmp/stuck"
echo untracked >"$tmp/stuck/untracked.txt"
busy_path="$tmp/stuck"
rm() {
	if [ "${3:-}" = "$tmp/stuck" ]; then
		echo "rm: $3: Directory not empty" >&2
		return 1
	fi
	command rm "$@"
}
load_deletion_worktrees
selected=$(deletion_candidates all | awk -F'\t' '$1 == "delete-stuck"')
delete_candidates "$selected" >"$tmp/delete-output" 2>&1
unset -f git rm
has 'a folder that stays busy gets a warning' "warning: could not delete '$tmp/stuck'" "$(<"$tmp/delete-output")"
is 'a folder that stays busy still loses its branch' '' "$(git branch --list delete-stuck)"
rm -rf "$tmp/stuck"

git worktree add -q -b order-dirty "$tmp/order-dirty"
echo untracked >"$tmp/order-dirty/untracked.txt"
git worktree add -q -b order-clean "$tmp/order-clean"
git branch order-plain
load_deletion_worktrees
selected=$'no-such-branch\tbranch\t[branch]\n'$(deletion_candidates all | awk -F'\t' '$1 ~ /^order-/')
status=0
(
	confirm() {
		printf 'clean=%s plain=%s\n' "$([ -e "$tmp/order-clean" ] && echo yes || echo no)" \
			"$(git branch --list order-plain)" >"$tmp/order-state"
	}
	delete_candidates "$selected"
) >"$tmp/delete-output" 2>&1 || status=$?
is 'questions come after the deletions that need none' 'clean=no plain=' "$(<"$tmp/order-state")"
is 'a failed entry leaves the rest deleted' '' "$(git branch --list 'order-*')"
is 'a failed entry makes the command fail' 1 "$status"
has 'a failed entry is reported' 'branch retained: no-such-branch' "$(<"$tmp/delete-output")"

load_deletion_worktrees
selected=$(deletion_candidates all | awk -F'\t' '$3 ~ /^\[worktree detached\]/ || $1 == "delete-odd"')
delete_candidates "$selected" >"$tmp/delete-output" 2>&1
is 'detached worktree folder is removed' no "$([ -e "$tmp/detached" ] && echo yes || echo no)"
is 'paths with tabs and newlines are removed exactly' no "$([ -e "$tmp/odd"$'\t\n'"path" ] && echo yes || echo no)"
is 'deleting a detached worktree keeps the current branch' main "$(git b)"

rm "$tmp/missing/file.txt" "$tmp/missing/.git"
rmdir "$tmp/missing"
export pick_branch=delete-missing
git db >"$tmp/delete-output" 2>&1
is 'git db removes a missing worktree registration and branch' '' "$(git branch --list delete-missing)"

git worktree add -q -b delete-shared "$tmp/shared-a"
git worktree add -q --force "$tmp/shared-b" delete-shared
load_deletion_worktrees
selected=$(deletion_candidates all | awk -F'\t' '$1 == "delete-shared" && !seen++')
delete_candidates "$selected" >"$tmp/delete-output" 2>&1
has 'removing one worktree keeps a shared branch' 'delete-shared' "$(git branch --list delete-shared)"
load_deletion_worktrees
selected=$(deletion_candidates all | awk -F'\t' '$1 == "delete-shared"')
delete_candidates "$selected" >"$tmp/delete-output" 2>&1
is 'removing the last worktree deletes a shared branch' '' "$(git branch --list delete-shared)"

git worktree add -q -b delete-parent "$tmp/parent"
git worktree add -q -b delete-child "$tmp/parent/child"
load_deletion_worktrees
candidates=$(deletion_candidates all)
is 'picker protects folders containing another worktree' '' "$(printf '%s\n' "$candidates" | awk -F'\t' '$1 == "delete-parent"')"
has 'nested worktree can be selected separately' 'delete-child' "$candidates"

git branch gone-plain
git worktree add -q -b gone-worktree "$tmp/gone"
git worktree add -q -b kept-worktree "$tmp/kept"
for branch in gone-plain gone-worktree delete-locked main; do
	git push -q origin "$branch:refs/heads/upstream-$branch"
	git branch --set-upstream-to="origin/upstream-$branch" "$branch" >/dev/null
	git push -q origin --delete "upstream-$branch"
done
git branch --set-upstream-to=origin/main kept-worktree >/dev/null
load_deletion_worktrees
selected=$(deletion_candidates gone)
has 'dbm candidates include plain branches' $'gone-plain\tbranch\t[branch]' "$selected"
has 'dbm candidates include worktrees' "[worktree] $tmp/gone" "$selected"
is 'dbm excludes locked worktrees' '' "$(printf '%s\n' "$selected" | grep -F delete-locked || true)"
is 'dbm excludes current branches with gone upstreams' '' "$(printf '%s\n' "$selected" | awk -F'\t' '$1 == "main"')"
is 'dbm keeps branches with existing upstreams' '' "$(printf '%s\n' "$selected" | grep -F kept-worktree || true)"
git branch prune-only
git push -qu origin prune-only
git --git-dir="$tmp/origin.git" update-ref -d refs/heads/prune-only
# Replace only the terminal prompt in a test copy of the command.
mkdir -p "$tmp/aliases/bin"
cp "$root/bin/git-dbm" "$root/bin/_lib.sh" "$tmp/aliases/bin/"
declare -f confirm >>"$tmp/aliases/bin/_lib.sh"
export delete_answer=yes
git -c gitaliases.dir="$tmp/aliases" dbm >"$tmp/delete-output" 2>&1
has 'git dbm displays branch labels' 'gone-plain [branch]' "$(<"$tmp/delete-output")"
has 'git dbm displays worktree labels' "gone-worktree [worktree] $tmp/gone" "$(<"$tmp/delete-output")"
is 'dbm deletion removes gone branches' '' "$(git branch --list 'gone-*')"
is 'git dbm fetches and prunes before finding candidates' '' "$(git branch --list prune-only)"
is 'dbm deletion removes gone worktree folders' no "$([ -e "$tmp/gone" ] && echo yes || echo no)"
is 'dbm leaves locked worktree files' yes "$([ -e "$tmp/locked/file.txt" ] && echo yes || echo no)"
is 'dbm leaves worktrees with a live upstream' yes "$([ -e "$tmp/kept/file.txt" ] && echo yes || echo no)"
is 'worktree cleanup keeps shared stash entries' "$shared_stash" "$(git rev-parse refs/stash)"

git branch --set-upstream-to=origin/main main >/dev/null

expected=$(git config --file "$root/aliases.gitconfig" --name-only --get-regexp '^alias\.' | grep -c .)
is 'git a lists every alias' "$expected" "$(git a | grep -c 'bin/git-')"

# ----------------------------------------------------------------------------

if [ "$failures" -gt 0 ]; then
	printf '\n%d of %d checks failed\n' "$failures" "$checks" >&2
	exit 1
fi

printf 'ok: %d checks\n' "$checks"
