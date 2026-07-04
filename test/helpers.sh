# Shared test framework — sourced by individual test files.
# Provides counters, colored output, case tracking, and common assertions.

pass=0 fail=0
green="$(printf '\033[0;32m')" red="$(printf '\033[0;31m')" reset="$(printf '\033[0m')"

# ── Case tracking ──
check() {
	_pb=$pass
	_fb=$fail
}
result() {
	local name="$1" p=$((pass - _pb)) f=$((fail - _fb))
	if [ "$f" -eq 0 ]; then
		printf "  ${green}✓${reset} %s\n" "$name"
	else
		printf "  ${red}✗${reset} %s  (%d fail)\n" "$name" "$f"
	fi
}

# ── Common assertions ──

# Exact whole-line, fixed-string file match (grep -qxF).
assert_file_contains() {
	local file="$1" pattern="$2"
	if grep -qxF "$pattern" "$file" 2>/dev/null; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		echo "  FAIL: expected '$pattern' in $(basename "$file")" >&2
	fi
}

assert_file_not_contains() {
	local file="$1" pattern="$2"
	if ! grep -qxF "$pattern" "$file" 2>/dev/null; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		echo "  FAIL: unexpected '$pattern' in $(basename "$file")" >&2
	fi
}

# Exact string match against captured helper calls.
assert_call_contains() {
	local arr_name="$1" expected="$2" color="$3"
	local -n arr="$arr_name"
	for call in "${arr[@]}"; do
		[ "$call" = "$expected" ] && {
			pass=$((pass + 1))
			return
		}
	done
	fail=$((fail + 1))
	echo "  FAIL: ${color}() not called with '${expected}'" >&2
}

# Verify no carriage return in a file (CRLF defence check).
assert_no_cr() {
	local file="$1"
	if grep -q $'\r' "$file" 2>/dev/null; then
		fail=$((fail + 1))
		echo "  FAIL: CR found in $(basename "$file")" >&2
	else
		pass=$((pass + 1))
	fi
}

# Verify a line appears exactly once — catches duplicate-appends.
assert_unique() {
	local file="$1" pattern="$2"
	local count=$(grep -cFx "$pattern" "$file" 2>/dev/null || echo 0)
	if [ "$count" -eq 1 ]; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		echo "  FAIL: '$pattern' appears ${count} times in $(basename "$file") (expected 1)" >&2
	fi
}

# Query global git config.
assert_git_config() {
	if [ "$(git config --global --get "$1" 2>/dev/null || true)" = "$2" ]; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		local got="$(git config --global --get "$1" 2>/dev/null || echo '<unset>')"
		echo "  FAIL: git config $1 expected '$2', got '$got'" >&2
	fi
}

# ── Summary ──
finish() {
	echo ""
	if [ "$fail" -eq 0 ]; then
		printf "  ${green}✓${reset} %d passed\n" "$pass"
	else
		printf "  ${red}✗${reset} %d passed, %d failed\n" "$pass" "$fail"
		exit 1
	fi
}
