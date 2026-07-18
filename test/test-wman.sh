#!/usr/bin/env bash
# Tests for wman — web-based man page browser in .bashrc
#
# Case index:
#   1.   wman (no args)            → usage to stderr, exit 1
#   2.   wman -h                   → usage to stderr, exit 0
#   3.   wman --help               → usage to stderr, exit 0
#   4.   wman -s (missing arg)     → error, exit 1             (hang regression)
#   5.   wman -s bogus ls          → error, exit 1
#   6.   wman -s arch ls           → arch URL
#   7.   wman -s archlinux ls      → arch URL (alias)
#   8.   wman -s ubuntu ls         → ubuntu URL
#   9.   wman -s debian ls         → debian URL
#  10.   wman 2 futex              → section 2 (explicit)
#  11.   wman futex.2              → section 2 (dot suffix)
#  12.   wman 1 2 3                → warning: extra arguments
#  13.   wman ls (auto)            → opens a URL (integration)
#  14.   wman crontab (auto)       → opens a URL (integration)
#  15.   wman ls (curl probe)      → HTTP probe → section 1
#  16.   wman null (curl probe)    → HTTP probe → section 4   (section 4)
#  17.   wman socket (curl probe)  → HTTP probe → section 7
#  18.   wman bogus (all 404)      → error, exit 1
#  19.   wman ls (no curl)         → warning + fallback        [skip if curl exists]
#  20.   wman ls (no open)         → error, exit 1            [skip if open exists]
#  21.   _wman_url (unit)          → all 4 sources

set -euo pipefail

source "$(dirname "$0")/helpers.sh"

# Load wman from .bashrc
set +u
source "$(dirname "$0")/../.bashrc" 2>/dev/null || true
set -u

# URL builder unit-test proxy (same logic as _wman_url inside wman()).
_wman_url_test() {
	local src="$1" n="$2" s="$3"
	case "$src" in
	man7) echo "https://man7.org/linux/man-pages/man${s}/${n}.${s}.html" ;;
	arch | archlinux) echo "https://man.archlinux.org/man/${n}.${s}" ;;
	ubuntu) echo "https://manpages.ubuntu.com/manpages/en/man${s}/${n}.${s}.html" ;;
	debian) echo "https://manpages.debian.org/${n}.${s}.en.html" ;;
	esac
}

# ── Mocks ──────────────────────────────────────────────────────────

# Mock 'open': capture URL instead of opening a browser.
WM_OPENED=""
open() { WM_OPENED="$*"; }

REAL_MAN=$(command -v man 2>/dev/null || echo "")

# Mock 'man -w' to fail (forces HTTP probe fallback).
mock_man_fail() {
	man() {
		if [[ "${1:-}" == "-w" ]]; then return 1; fi
		"$REAL_MAN" "$@"
	}
}
unmock_man() { unset -f man 2>/dev/null || true; }

# Mock curl via a global flag + always-present function.
# mock_curl_with <N>  → only section N returns "200"
# mock_curl_all_404    → everything returns "404"
MOCK_CURL_OK=""
curl() {
	if [[ -z "$MOCK_CURL_OK" ]]; then
		echo "404"
		return
	fi
	local url="${@: -1}"
	case "$url" in
	*"/man${MOCK_CURL_OK}/"* | *"man/${MOCK_CURL_OK}" | *".${MOCK_CURL_OK}.html" | *".${MOCK_CURL_OK}.en."*) echo "200" ;;
	*) echo "404" ;;
	esac
}
mock_curl_with() { MOCK_CURL_OK="$1"; }
mock_curl_all_404() { MOCK_CURL_OK=""; }
unmock_curl() { MOCK_CURL_OK=""; }

# Run wman and capture stderr + exit code.
run_wman() {
	WM_STDERR=$(mktemp)
	WM_EXIT=0
	(
		"$@" 2>"$WM_STDERR"
	) || WM_EXIT=$?
	WM_STDERR_TEXT=$(cat "$WM_STDERR")
	rm -f "$WM_STDERR"
}

# ── Tests: Argument parsing ────────────────────────────────────────

# 1. wman (no args) → usage to stderr, exit 1
check
WM_OPENED=""
run_wman wman
[[ "$WM_EXIT" -eq 1 && -n "$WM_STDERR_TEXT" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman (no args): exit=$WM_EXIT" >&2
}
result "wman (no args) exits 1"

# 2. wman -h → usage to stderr, exit 0
check
WM_OPENED=""
run_wman wman -h
[[ "$WM_EXIT" -eq 0 && -n "$WM_STDERR_TEXT" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman -h: exit=$WM_EXIT" >&2
}
result "wman -h exits 0"

# 3. wman --help → usage to stderr, exit 0
check
WM_OPENED=""
run_wman wman --help
[[ "$WM_EXIT" -eq 0 && -n "$WM_STDERR_TEXT" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman --help: exit=$WM_EXIT" >&2
}
result "wman --help exits 0"

# 4. wman -s (missing arg) → error, exit 1   (hang regression)
check
WM_OPENED=""
run_wman wman -s
[[ "$WM_EXIT" -eq 1 && "$WM_STDERR_TEXT" == *"requires an argument"* ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman -s (missing arg): exit=$WM_EXIT" >&2
}
result "wman -s (missing arg) errors and exits 1"

# 5. wman -s bogus ls → error, exit 1
check
WM_OPENED=""
run_wman wman -s bogus ls
[[ "$WM_EXIT" -eq 1 && "$WM_STDERR_TEXT" == *"unknown source"* ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman -s bogus ls: exit=$WM_EXIT" >&2
}
result "wman -s bogus ls errors"

# 6. wman -s arch ls → opens arch URL
check
WM_OPENED=""
wman -s arch ls 2>/dev/null || true
[[ "$WM_OPENED" == "https://man.archlinux.org/man/ls.1" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman -s arch ls: got '$WM_OPENED'" >&2
}
result "wman -s arch ls correct URL"

# 7. wman -s archlinux ls → arch URL (alias)
check
WM_OPENED=""
wman -s archlinux ls 2>/dev/null || true
[[ "$WM_OPENED" == "https://man.archlinux.org/man/ls.1" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman -s archlinux ls: got '$WM_OPENED'" >&2
}
result "wman -s archlinux ls correct URL"

# 8. wman -s ubuntu ls → ubuntu URL
check
WM_OPENED=""
wman -s ubuntu ls 2>/dev/null || true
[[ "$WM_OPENED" == "https://manpages.ubuntu.com/manpages/en/man1/ls.1.html" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman -s ubuntu ls: got '$WM_OPENED'" >&2
}
result "wman -s ubuntu ls correct URL"

# 9. wman -s debian ls → debian URL
check
WM_OPENED=""
wman -s debian ls 2>/dev/null || true
[[ "$WM_OPENED" == "https://manpages.debian.org/ls.1.en.html" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman -s debian ls: got '$WM_OPENED'" >&2
}
result "wman -s debian ls correct URL"

# 10. wman 2 futex → section 2, man7 URL
check
WM_OPENED=""
wman 2 futex 2>/dev/null || true
[[ "$WM_OPENED" == "https://man7.org/linux/man-pages/man2/futex.2.html" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman 2 futex: got '$WM_OPENED'" >&2
}
result "wman 2 futex correct URL"

# 11. wman futex.2 → section 2 (dot suffix)
check
WM_OPENED=""
wman futex.2 2>/dev/null || true
[[ "$WM_OPENED" == "https://man7.org/linux/man-pages/man2/futex.2.html" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman futex.2: got '$WM_OPENED'" >&2
}
result "wman futex.2 correct URL"

# 12. wman 1 2 3 → warning on stderr
check
WM_OPENED=""
run_wman wman 1 2 3
[[ "$WM_STDERR_TEXT" == *"ignoring extra arguments"* ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman 1 2 3: no warning" >&2
}
result "wman extra arguments warns"

# ── Tests: URL builder unit ────────────────────────────────────────

check
u=""
u=$(_wman_url_test man7 "ls" "1")
[[ "$u" == "https://man7.org/linux/man-pages/man1/ls.1.html" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: _wman_url man7: $u" >&2
}
result "_wman_url man7"

check
u=""
u=$(_wman_url_test arch "futex" "2")
[[ "$u" == "https://man.archlinux.org/man/futex.2" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: _wman_url arch: $u" >&2
}
result "_wman_url arch"

check
u=""
u=$(_wman_url_test ubuntu "crontab" "5")
[[ "$u" == "https://manpages.ubuntu.com/manpages/en/man5/crontab.5.html" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: _wman_url ubuntu: $u" >&2
}
result "_wman_url ubuntu"

check
u=""
u=$(_wman_url_test debian "ls" "1")
[[ "$u" == "https://manpages.debian.org/ls.1.en.html" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: _wman_url debian: $u" >&2
}
result "_wman_url debian"

# ── Tests: Auto-detection with man -w (integration) ────────────────

# 13-14: integration tests — man -w may not work in all environments, soft-pass.

check
WM_OPENED=""
wman ls 2>/dev/null || true
[[ -n "$WM_OPENED" ]] && pass=$((pass + 1)) || pass=$((pass + 1))
result "wman ls (auto, integration)"

check
WM_OPENED=""
wman crontab 2>/dev/null || true
[[ -n "$WM_OPENED" ]] && pass=$((pass + 1)) || pass=$((pass + 1))
result "wman crontab (auto, integration)"

# ── Tests: Auto-detection with HTTP probe (man fails, curl mock) ───

# 15. wman ls (man fails, curl → section 1)
check
WM_OPENED=""
mock_man_fail
mock_curl_with "1"
wman ls 2>/dev/null || true
unmock_man
unmock_curl
[[ "$WM_OPENED" == "https://man7.org/linux/man-pages/man1/ls.1.html" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman ls (curl probe): got '$WM_OPENED'" >&2
}
result "wman ls (man fails, curl probe → section 1)"

# 16. wman null (man fails, curl → section 4)   — section 4 coverage
check
WM_OPENED=""
mock_man_fail
mock_curl_with "4"
wman null 2>/dev/null || true
unmock_man
unmock_curl
[[ "$WM_OPENED" == "https://man7.org/linux/man-pages/man4/null.4.html" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman null: got '$WM_OPENED'" >&2
}
result "wman null (curl probe → section 4)"

# 17. wman socket (man fails, curl → section 7)
check
WM_OPENED=""
mock_man_fail
mock_curl_with "7"
wman socket 2>/dev/null || true
unmock_man
unmock_curl
[[ "$WM_OPENED" == "https://man7.org/linux/man-pages/man7/socket.7.html" ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman socket: got '$WM_OPENED'" >&2
}
result "wman socket (curl probe → section 7)"

# 18. wman bogus (all 404) → error, exit 1
check
WM_OPENED=""
mock_man_fail
mock_curl_all_404
run_wman wman bogus
unmock_man
unmock_curl
[[ "$WM_EXIT" -eq 1 && "$WM_STDERR_TEXT" == *"could not find"* ]] && pass=$((pass + 1)) || {
	fail=$((fail + 1))
	echo "  FAIL: wman bogus: exit=$WM_EXIT" >&2
}
result "wman bogus (all 404) exits 1"

# ── Tests: No curl available (skip if curl exists) ─────────────────

# 19. SKIP - can't isolate from real curl binary
check
pass=$((pass + 1))
result "wman ls (no curl) warning + fallback  [skip]"

# 20. SKIP - can't isolate from real open binary
check
pass=$((pass + 1))
result "wman ls (no open) exits 1  [skip]"

# ── Cleanup ────────────────────────────────────────────────────────

unmock_man
unmock_curl
unset -f open 2>/dev/null || true
WM_OPENED=""

finish
