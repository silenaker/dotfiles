#!/usr/bin/env bash
# Tests for fztype (three-mode) and _fzmatch in .bashrc
#
# Modes:
#   (default)  Cached non-prefix fuzzy + lazy bg refresh
#   -p         Prefix real-time fuzzy, no cache I/O
#   -r         Non-prefix real-time fuzzy + atomic cache update
#
# Cases:
#   1.  _fzmatch exact match
#   2.  _fzmatch fuzzy match (scattered)
#   3.  _fzmatch fuzzy match (mid-string)
#   4.  _fzmatch no match (wrong order)
#   5.  fztype no argument
#   6.  fztype no match
#   7.  fztype -p finds file command
#   8.  fztype -p finds builtin
#   9.  fztype -p finds alias
#  10.  fztype -p fuzzy-match pyth3 → python3
#  11.  fztype -r populates cache
#  12.  fztype -r non-prefix fuzzy match
#  13.  fztype (default) reads from cache
#  14.  fztype (default) missing cache fallback
#  15.  fztype (default) expired cache returns results
set -euo pipefail

source "$(dirname "$0")/helpers.sh"

# Load fztype and _fzmatch from .bashrc
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
# _fzmatch
# ------------------------------------------------------------------

# --- exact ---------------------------------------------------------
check
if _fzmatch "git" "git"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: exact match" >&2
fi
result "_fzmatch exact"

# --- fuzzy (scattered) ---------------------------------------------
check
if _fzmatch "pyth" "python3"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: pyth → python3" >&2
fi
result "_fzmatch fuzzy (scattered)"

# --- fuzzy (mid-string) --------------------------------------------
check
if _fzmatch "thon" "python3"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: thon → python3" >&2
fi
result "_fzmatch fuzzy (mid-string)"

# --- no match (wrong order) ----------------------------------------
check
if ! _fzmatch "tp" "python3"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: tp should NOT match python3" >&2
fi
result "_fzmatch no match (wrong order)"

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
out=$(fztype bash 2>/dev/null) || true
if grep -q 'bash' <<<"$out"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: expired cache should still return results" >&2
fi
result "fztype default expired cache"

# ------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------
rm -rf "$(dirname "$TEST_CACHE")"

finish
