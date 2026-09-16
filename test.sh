#!/usr/bin/env bash
# Runs the aliases against a throwaway repo, with a throwaway HOME, and checks
# what they did. Touches nothing outside its temp directory.
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
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

has 'git dbm finds nothing to delete' 'No local branches with a gone upstream.' "$(git dbm 2>&1)"
has 'git dwm finds nothing to remove' 'No worktrees with a gone upstream.' "$(git dwm 2>&1)"

expected=$(git config --file "$root/aliases.gitconfig" --name-only --get-regexp '^alias\.' | grep -c .)
is 'git a lists every alias' "$expected" "$(git a | grep -c 'bin/git-')"

# ----------------------------------------------------------------------------

if [ "$failures" -gt 0 ]; then
	printf '\n%d of %d checks failed\n' "$failures" "$checks" >&2
	exit 1
fi

printf 'ok: %d checks\n' "$checks"
