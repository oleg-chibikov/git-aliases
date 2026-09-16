#!/usr/bin/env bash
# Checks that the aliases keep their shape: one script per alias, a description
# comment on every script, a row in the README, and clean shell.
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
cd "$root"

config='aliases.gitconfig'
readme='README.md'
# shellcheck disable=SC2016  # this is the literal alias body, nothing to expand
prefix='!"$(git config gitaliases.dir)"/bin/'

failures=0

fail() {
	printf 'FAIL %s\n' "$*" >&2
	failures=$((failures + 1))
}

# --- aliases.gitconfig ------------------------------------------------------

names=()
scripts=()
while IFS= read -r -d '' entry; do
	name=${entry%%$'\n'*}
	name=${name#alias.}
	value=${entry#*$'\n'}

	if [[ $value != "$prefix"* ]]; then
		fail "$config: alias '$name' does not run a bin/ script: $value"
		continue
	fi

	script=${value#"$prefix"}
	if [[ ! $script =~ ^git-[a-z0-9-]+$ ]]; then
		fail "$config: alias '$name' has an odd script name: $script"
		continue
	fi
	[ -f "bin/$script" ] || fail "$config: alias '$name' points at missing bin/$script"

	names+=("$name")
	scripts+=("$script")
done < <(git config --file "$config" --null --get-regexp '^alias\.')

[ ${#names[@]} -gt 0 ] || fail "$config: no aliases found"

sorted=$(printf '%s\n' ${names[@]+"${names[@]}"} | LC_ALL=C sort)
if [ "$sorted" != "$(printf '%s\n' ${names[@]+"${names[@]}"})" ]; then
	fail "$config: aliases are not sorted alphabetically"
fi

while IFS= read -r line; do
	case $line in
		'' | '#'* | '[alias]') continue ;;
		$'\t'*' = "!'*'"') continue ;;
		*) fail "$config: line is not <tab>name = \"!...\": $line" ;;
	esac
done <"$config"

# --- scripts ----------------------------------------------------------------

script_count=0
for script in bin/git-*; do
	script_count=$((script_count + 1))
	[ -x "$script" ] || fail "$script: not executable, run chmod +x"

	first=$(head -n 1 "$script")
	[ "$first" = '#!/usr/bin/env bash' ] || fail "$script: first line must be #!/usr/bin/env bash"

	second=$(sed -n '2p' "$script")
	case $second in
		'# '?*) ;;
		*) fail "$script: line 2 must be a '# ' description comment" ;;
	esac

	grep -qx 'set -euo pipefail' "$script" || fail "$script: missing 'set -euo pipefail'"

	name=${script#bin/}
	found=0
	for used in ${scripts[@]+"${scripts[@]}"}; do
		if [ "$used" = "$name" ]; then
			found=1
		fi
	done
	[ "$found" = 1 ] || fail "$script: no alias in $config runs it"
done

[ ! -x bin/_lib.sh ] || fail 'bin/_lib.sh: sourced, not run, so it should not be executable'

for script in install.sh lint.sh hooks/pre-commit; do
	[ -x "$script" ] || fail "$script: not executable, run chmod +x"
done

# --- README -----------------------------------------------------------------

for name in ${names[@]+"${names[@]}"}; do
	grep -qF "\`$name\`" "$readme" || fail "$readme: alias '$name' is not documented"
done

# --- shell tooling ----------------------------------------------------------

if command -v shellcheck >/dev/null 2>&1; then
	shellcheck --external-sources bin/* ./*.sh hooks/* || fail 'shellcheck reported problems'
else
	echo 'skipped shellcheck (not installed: brew install shellcheck)'
fi

if command -v shfmt >/dev/null 2>&1; then
	shfmt --diff --case-indent bin/* ./*.sh hooks/* ||
		fail 'shfmt reported formatting problems, run: shfmt --write --case-indent bin/* ./*.sh hooks/*'
else
	echo 'skipped shfmt (not installed: brew install shfmt)'
fi

# ----------------------------------------------------------------------------

if [ "$failures" -gt 0 ]; then
	printf '\n%d problem(s)\n' "$failures" >&2
	exit 1
fi

printf 'ok: %d aliases, %d scripts\n' "${#names[@]}" "$script_count"
