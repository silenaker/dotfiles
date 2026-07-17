#!/usr/bin/env bash
# Tests for fztype (three-mode) and _fztype_match in .bashrc
#
# Modes:
#   (default)  Cached non-prefix fuzzy + lazy bg refresh
#   -p         Prefix real-time fuzzy, no cache I/O
#   -r         Non-prefix real-time fuzzy + atomic cache update
#
# Cases:
#   1.  _fztype_match exact match
#   2.  _fztype_match fuzzy match (scattered)
#   3.  _fztype_match fuzzy match (mid-string)
#   4.  _fztype_match no match (wrong order)
#   5.  fztype no argument
#   6.  fztype no match
#   7.  fztype -p -r mutually exclusive (prefix first)
#   8.  fztype -r -p mutually exclusive (refresh first)
#   9.  fztype -p finds file command
#  10.  fztype -p finds builtin
#  11.  fztype -p finds alias
#  12.  fztype -p fuzzy-match pyth3 → python3
#  13.  fztype -r populates cache
#  14.  fztype -r non-prefix fuzzy match
#  15.  fztype (default) reads from cache
#  16.  fztype (default) missing cache fallback
#  17.  fztype (default) expired cache
#  18.  fztype -t alias
#  19.  fztype -p -t builtin
#  20.  fztype -t invalid type
#  21.  fztype -t file fuzzy
set -euo pipefail

source "$(dirname "$0")/helpers.sh"

# Load fztype and _fztype_match from .bashrc
set +u
source "$(dirname "$0")/../.bashrc" 2>/dev/null || true
set -u

# Isolated cache directory for tests.
TEST_CACHE="$(mktemp -d)/fztype"
export XDG_CACHE_HOME="$(dirname "$TEST_CACHE")"
CACHE_FILE="$TEST_CACHE/commands"

reset_cache() { rm -rf "$TEST_CACHE"; }
write_cache() { mkdir -p "$TEST_CACHE" && printf '%s\n' "$1" >"$CACHE_FILE"; }

# ------------------------------------------------------------------
# _fztype_match
# ------------------------------------------------------------------

# --- exact ---------------------------------------------------------
check
if _fztype_match "git" "git"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: exact match" >&2
fi
result "_fztype_match exact"

# --- fuzzy (scattered) ---------------------------------------------
check
if _fztype_match "pyth" "python3"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: pyth → python3" >&2
fi
result "_fztype_match fuzzy (scattered)"

# --- fuzzy (mid-string) --------------------------------------------
check
if _fztype_match "thon" "python3"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: thon → python3" >&2
fi
result "_fztype_match fuzzy (mid-string)"

# --- no match (wrong order) ----------------------------------------
check
if ! _fztype_match "tp" "python3"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: tp should NOT match python3" >&2
fi
result "_fztype_match no match (wrong order)"

# ------------------------------------------------------------------
# Error handling
# ------------------------------------------------------------------

# --- no argument ---------------------------------------------------
reset_cache
check
if ! fztype 2>/dev/null; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: no arg should fail" >&2
fi
result "fztype no argument"

# --- no match ------------------------------------------------------
reset_cache
check
if ! fztype "zzzNOSUCHCMDxxx" 2>/dev/null; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: bogus cmd should fail" >&2
fi
result "fztype no match"

# --- -p and -r mutually exclusive (prefix first) --------------------
reset_cache
check
if ! fztype -p -r bash 2>/dev/null; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: -p -r should be rejected" >&2
fi
result "fztype -p -r rejected"

# --- -p and -r mutually exclusive (refresh first) -------------------
reset_cache
check
if ! fztype -r -p bash 2>/dev/null; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: -r -p should be rejected" >&2
fi
result "fztype -r -p rejected"

# ------------------------------------------------------------------
# fztype -p (prefix)
# ------------------------------------------------------------------

# --- file command --------------------------------------------------
reset_cache
check
out=$(fztype -p bash 2>/dev/null) || true
if grep -q 'bash' <<<"$out"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: -p bash should find bash" >&2
fi
result "fztype -p file command"

# --- builtin -------------------------------------------------------
reset_cache
check
out=$(fztype -p cd 2>/dev/null) || true
if grep -q '\[builtin\]' <<<"$out"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: -p cd should show [builtin]" >&2
fi
result "fztype -p builtin"

# --- alias ---------------------------------------------------------
reset_cache
check
alias _fztest_xyz123='echo hello'
out=$(fztype -p _fztest_xyz123 2>/dev/null) || true
if grep -q '\[alias\]' <<<"$out"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: -p should show [alias]" >&2
fi
unalias _fztest_xyz123 2>/dev/null || true
result "fztype -p alias"

# --- fuzzy ---------------------------------------------------------
reset_cache
check
out=$(fztype -p pyth3 2>/dev/null) || true
if grep -q 'python3' <<<"$out"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: -p pyth3 should fuzzy-match python3" >&2
fi
result "fztype -p fuzzy (pyth3 → python3)"

# ------------------------------------------------------------------
# fztype -r (refresh)
# ------------------------------------------------------------------

# --- populate cache ------------------------------------------------
reset_cache
check
fztype -r bash &>/dev/null || true
sleep 0.3
if [ -s "$CACHE_FILE" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: -r should populate cache" >&2
fi
result "fztype -r populate cache"

# --- non-prefix fuzzy ----------------------------------------------
reset_cache
check
out=$(fztype -r thon 2>/dev/null) || true
if grep -q 'python3' <<<"$out"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: -r thon should match python3" >&2
fi
result "fztype -r non-prefix fuzzy (thon → python3)"

# ------------------------------------------------------------------
# fztype (default)
# ------------------------------------------------------------------

# --- read from cache -----------------------------------------------
reset_cache
check
write_cache "bash\npython3\npython3.10\ngit\nmycmd"
out=$(fztype pyth3 2>/dev/null) || true
if grep -q 'python3' <<<"$out"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: should read from cache" >&2
fi
result "fztype default read from cache"

# --- missing cache fallback ----------------------------------------
reset_cache
check
out=$(fztype bash 2>/dev/null) || true
sleep 0.3
if grep -q 'bash' <<<"$out" && [ -s "$CACHE_FILE" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: should fall back to -r" >&2
fi
result "fztype default missing cache fallback"

# --- expired cache -------------------------------------------------
reset_cache
check
write_cache "bash\npython3\ngit"
touch -d "yesterday" "$CACHE_FILE"
before_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
out=$(fztype bash 2>/dev/null) || true
if grep -q 'bash' <<<"$out"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: expired cache should still return results" >&2
fi
# Poll for background refresh to update commands mtime, 30s timeout.
waited=0 refreshed=0
while [ "$waited" -lt 30 ]; do
    cur_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
    if [ "$cur_mtime" -gt "$before_mtime" ] 2>/dev/null; then
        refreshed=1
        break
    fi
    sleep 1
    waited=$((waited + 1))
done
if [ "$refreshed" -eq 1 ] && [ ! -f "$TEST_CACHE/commands.tmp" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: expired cache should trigger refresh and leave no tmp" >&2
fi
result "fztype default expired cache"

# ------------------------------------------------------------------
# fztype -t (type filter)
# ------------------------------------------------------------------

# --- type filter alias ----------------------------------------------
reset_cache
check
alias _fztest_foo42='echo bar'
out=$(fztype -t alias _fztest 2>/dev/null) || true
if grep -q '\[alias\]' <<<"$out" && ! grep -q '\[builtin\]' <<<"$out"; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "  FAIL: -t alias should only show aliases" >&2
fi
unalias _fztest_foo42 2>/dev/null || true
result "fztype -t alias"

# --- type filter builtin with -p ------------------------------------
reset_cache
check
out=$(fztype -p -t builtin cd 2>/dev/null) || true
if grep -q 'cd' <<<"$out" && grep -q '\[builtin\]' <<<"$out"; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "  FAIL: -p -t builtin cd should find cd [builtin]" >&2
fi
result "fztype -p -t builtin"

# --- type filter invalid type ---------------------------------------
reset_cache
check
if ! fztype -t bogus bash 2>/dev/null; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "  FAIL: -t bogus should fail" >&2
fi
result "fztype -t invalid type"

# --- type filter file with fuzzy match ------------------------------
reset_cache
check
out=$(fztype -t file pyth3 2>/dev/null) || true
if grep -q 'python3' <<<"$out" && ! grep -q '\[alias\]' <<<"$out"; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "  FAIL: -t file pyth3 should match python3 as file type" >&2
fi
result "fztype -t file fuzzy"

# ------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------
rm -rf "$(dirname "$TEST_CACHE")"

finish
