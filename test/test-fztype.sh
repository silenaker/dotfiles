#!/usr/bin/env bash
# Unit tests for fztype and _fzmatch in .bashrc
#
# fztype uses compgen + _fzmatch to fuzzy-match commands,
# then classifies each match via type -t / type -p.
#
# Cases:
#   1. _fzmatch exact match              — pattern equals target
#   2. _fzmatch fuzzy match              — chars scattered in target
#   3. _fzmatch fuzzy match (mid-string) — non-prefix subsequence
#   4. _fzmatch no match (char missing)  — pattern char absent
#   5. _fzmatch no match (wrong order)   — chars out of sequence
#   6. _fzmatch empty pattern            — vacuously true
#   7. _fzmatch empty pattern + target   — both empty
#   8. _fzmatch non-empty vs empty       — should fail
#   9. fztype no argument               — usage error
#  10. fztype no match                  — error with message
#  11. fztype finds file command        — shows path
#  12. fztype finds builtin             — shows [builtin]
#  13. fztype finds alias               — shows [alias]
#  14. fztype finds function            — shows [function]
#  15. fztype finds keyword             — shows [keyword]
#  16. fztype fuzzy-match pyth3 → python3
set -euo pipefail

source "$(dirname "$0")/helpers.sh"

# fztype lives in .bashrc; source to load both _fzmatch and fztype.
set +u
source "$(dirname "$0")/../.bashrc" 2>/dev/null || true
set -u

# ------------------------------------------------------------------
# _fzmatch unit tests (internal helper)
# ------------------------------------------------------------------

# --- exact match ----------------------------------------------------
check
if _fzmatch "git" "git"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL: exact match" >&2; fi
result "_fzmatch exact match"

# --- fuzzy match (chars scattered) ----------------------------------
check
if _fzmatch "pyth" "python3"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL: fuzzy match pyth → python3" >&2; fi
result "_fzmatch fuzzy match (scattered)"

# --- fuzzy match (subsequence, not prefix) --------------------------
check
if _fzmatch "thon" "python3"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL: fuzzy match thon → python3" >&2; fi
result "_fzmatch fuzzy match (mid-string)"

# --- no match (char missing) ----------------------------------------
check
if ! _fzmatch "xyz" "python3"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL: xyz should NOT match python3" >&2; fi
result "_fzmatch no match (char missing)"

# --- no match (wrong order) -----------------------------------------
check
if ! _fzmatch "tp" "python3"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL: tp should NOT match python3" >&2; fi
result "_fzmatch no match (wrong order)"

# --- empty pattern always matches -----------------------------------
check
if _fzmatch "" "anything"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL: empty pattern should match anything" >&2; fi
result "_fzmatch empty pattern"

# --- empty target, empty pattern ------------------------------------
check
if _fzmatch "" ""; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL: empty pattern should match empty target" >&2; fi
result "_fzmatch empty pattern + empty target"

# --- empty target, non-empty pattern --------------------------------
check
if ! _fzmatch "x" ""; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL: non-empty pattern should NOT match empty target" >&2; fi
result "_fzmatch non-empty pattern vs empty target"

# ------------------------------------------------------------------
# fztype integration tests
# ------------------------------------------------------------------

# --- no argument ----------------------------------------------------
check
if ! fztype 2>/dev/null; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL: fztype with no arg should fail" >&2; fi
result "fztype no argument"

# --- no match -------------------------------------------------------
check
if ! fztype "zzzNOSUCHCMDxxx" 2>/dev/null; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL: fztype with bogus cmd should fail" >&2; fi
result "fztype no match"

# --- finds a known file command ------------------------------------
check
# 'bash' is virtually guaranteed to exist on PATH.
out=$(fztype bash 2>/dev/null) || true
if grep -q 'bash' <<< "$out"; then
	pass=$((pass + 1))
else
	fail=$((fail + 1))
	echo "  FAIL: fztype bash should find bash" >&2
fi
result "fztype finds file command (bash)"

# --- finds a builtin ------------------------------------------------
check
out=$(fztype cd 2>/dev/null) || true
if grep -q '\[builtin\]' <<< "$out"; then
	pass=$((pass + 1))
else
	fail=$((fail + 1))
	echo "  FAIL: fztype cd should show [builtin]" >&2
fi
result "fztype finds builtin"

# --- finds an alias -------------------------------------------------
check
alias _fztest_xyz123='echo hello'
out=$(fztype _fztest_xyz123 2>/dev/null) || true
if grep -q '\[alias\]' <<< "$out"; then
	pass=$((pass + 1))
else
	fail=$((fail + 1))
	echo "  FAIL: fztype should show [alias] for an alias" >&2
fi
unalias _fztest_xyz123 2>/dev/null || true
result "fztype finds alias"

# --- finds a function -----------------------------------------------
check
_fztest_myfunc() { echo "test"; }
out=$(fztype _fztest_myfunc 2>/dev/null) || true
if grep -q '\[function\]' <<< "$out"; then
	pass=$((pass + 1))
else
	fail=$((fail + 1))
	echo "  FAIL: fztype should show [function] for a function" >&2
fi
unset -f _fztest_myfunc 2>/dev/null || true
result "fztype finds function"

# --- finds a keyword ------------------------------------------------
check
out=$(fztype if 2>/dev/null) || true
if grep -q '\[keyword\]' <<< "$out"; then
	pass=$((pass + 1))
else
	fail=$((fail + 1))
	echo "  FAIL: fztype should show [keyword] for 'if'" >&2
fi
result "fztype finds keyword"

# --- fuzzy match excludes prefix-only matches -----------------------
check
out=$(fztype pyth3 2>/dev/null) || true
if grep -q 'python3' <<< "$out"; then
	pass=$((pass + 1))
else
	fail=$((fail + 1))
	echo "  FAIL: fztype pyth3 should fuzzy-match python3" >&2
fi
result "fztype fuzzy-match pyth3 → python3"

finish
