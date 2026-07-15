#!/usr/bin/env bash
# Unit tests for lib/merge-bashrc.sh
#
# merge_bashrc merges .bashrc using managed-block markers
# (BASH_MARKER_START / BASH_MARKER_END from lib/constants.sh).
#
# Cases:
#   1. src missing                    — error path
#   2. dst does not exist             — first install, src copied as-is
#   3. dst exists, no markers         — block appended
#   4. dst has markers, content same  — skip (up to date)
#   5. dst has markers, content diff  — block updated, user content preserved
#   6. user content before and after  — both preserved on update
#   7. CRLF handling                  — \r stripped from src
#   8. idempotency                    — second run no-ops
set -euo pipefail

source "$(dirname "$0")/helpers.sh"
source "$(dirname "$0")/../lib/constants.sh"

# ------------------------------------------------------------------
# Stub helpers
# ------------------------------------------------------------------
GREEN_CALLS=()
DIM_CALLS=()
green() { GREEN_CALLS+=("$*"); }
dim() { DIM_CALLS+=("$*"); }
reset_calls() {
	GREEN_CALLS=()
	DIM_CALLS=()
}

assert_green_contains() { assert_call_contains GREEN_CALLS "$1" "green"; }
assert_dim_contains() { assert_call_contains DIM_CALLS "$1" "dim"; }

# ------------------------------------------------------------------
source "$(dirname "$0")/../lib/merge-bashrc.sh"

WORK="$(mktemp -d)"
trap "rm -rf $WORK" EXIT

# --- src missing ---------------------------------------------------
# Input:  nonexistent src path.
# Expect: return 1.
check
if merge_bashrc "/nonexistent/src" "$WORK/dst" 2>/dev/null; then
	fail=$((fail + 1))
	echo "  FAIL: expected non-zero exit" >&2
else
	pass=$((pass + 1))
fi
result "src missing"

# --- dst does not exist --------------------------------------------
# Input:  src has aliases, history settings.  dst does not exist.
# Expect: dst created as copy of src.
check
cat >"$WORK/src" <<'EOF'
HISTSIZE=10000
alias ll='ls -alF'
alias la='ls -A'
EOF
rm -f "$WORK/dst"
reset_calls
merge_bashrc "$WORK/src" "$WORK/dst"
assert_file_contains "$WORK/dst" "HISTSIZE=10000"
assert_file_contains "$WORK/dst" "alias ll='ls -alF'"
assert_file_contains "$WORK/dst" "alias la='ls -A'"
assert_green_contains "  + .bashrc (created)"
rm -f "$WORK/dst"
result "dst does not exist"

# --- dst exists, no markers ----------------------------------------
# Input:  dst has user content (pre-existing .bashrc).  No markers.
#         src has new aliases.
# Expect: src content appended inside markers, user content untouched.
check
cat >"$WORK/src" <<'EOF'
alias ll='ls -alF'
alias la='ls -A'
EOF
printf 'export MY_VAR=42\n' >"$WORK/dst"
reset_calls
merge_bashrc "$WORK/src" "$WORK/dst"
assert_file_contains "$WORK/dst" "export MY_VAR=42"
assert_file_contains "$WORK/dst" "$BASH_MARKER_START"
assert_file_contains "$WORK/dst" "alias ll='ls -alF'"
assert_file_contains "$WORK/dst" "alias la='ls -A'"
assert_file_contains "$WORK/dst" "$BASH_MARKER_END"
assert_green_contains "  + .bashrc block appended"
# User line comes before the block
user_ln="$(grep -n 'export MY_VAR=42' "$WORK/dst" | head -1 | cut -d: -f1)"
marker_ln="$(grep -n "$BASH_MARKER_START" "$WORK/dst" | head -1 | cut -d: -f1)"
if [ -n "$user_ln" ] && [ -n "$marker_ln" ]; then
	if [ "$user_ln" -lt "$marker_ln" ]; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		echo "  FAIL: user content should appear before managed block" >&2
	fi
else
	fail=$((fail + 1))
	echo "  FAIL: could not find lines for ordering check" >&2
fi
result "dst exists, no markers"

# --- dst has markers, content same ---------------------------------
# Input:  dst already has the managed block with same content.
# Expect: nothing changed, report "up to date".
check
cat >"$WORK/src" <<'EOF'
alias ll='ls -alF'
alias la='ls -A'
EOF
{
	printf 'export MY_VAR=42\n\n'
	printf '%s\n' "$BASH_MARKER_START"
	printf "alias ll='ls -alF'\nalias la='ls -A'\n"
	printf '%s\n' "$BASH_MARKER_END"
} >"$WORK/dst"
reset_calls
merge_bashrc "$WORK/src" "$WORK/dst"
assert_file_contains "$WORK/dst" "export MY_VAR=42"
assert_file_contains "$WORK/dst" "alias ll='ls -alF'"
assert_green_contains "  (up to date)"
result "dst has markers, content same"

# --- dst has markers, content different ----------------------------
# Input:  dst has managed block with old aliases.  src has new ones.
# Expect: block replaced, user content preserved outside block.
check
cat >"$WORK/src" <<'EOF'
alias ll='ls -alF'
alias la='ls -A'
alias grep='grep --color=auto'
EOF
{
	printf 'export MY_VAR=42\n\n'
	printf '%s\n' "$BASH_MARKER_START"
	printf "alias ll='ls -alF'\nalias la='ls -A'\n"
	printf '%s\n' "$BASH_MARKER_END"
} >"$WORK/dst"
reset_calls
merge_bashrc "$WORK/src" "$WORK/dst"
assert_file_contains "$WORK/dst" "export MY_VAR=42"
assert_file_contains "$WORK/dst" "alias grep='grep --color=auto'"
assert_green_contains "  + .bashrc block updated"
# Old alias lines should be gone (replaced by new content)
# But user content should remain
assert_file_contains "$WORK/dst" "export MY_VAR=42"
# Start marker appears exactly once
assert_unique "$WORK/dst" "$BASH_MARKER_START"
result "dst has markers, content diff"

# --- user content before and after ---------------------------------
# Input:  dst has user content above AND below the managed block.
# Expect: both user sections preserved, only block updated.
check
cat >"$WORK/src" <<'EOF'
alias ll='ls -alF'
alias ..='cd ..'
EOF
{
	printf 'export HELLO=world\n\n'
	printf '%s\n' "$BASH_MARKER_START"
	printf "alias ll='ls -alF'\n"
	printf '%s\n' "$BASH_MARKER_END"
	printf '\nexport GOODBYE=farewell\n'
} >"$WORK/dst"
reset_calls
merge_bashrc "$WORK/src" "$WORK/dst"
assert_file_contains "$WORK/dst" "export HELLO=world"
assert_file_contains "$WORK/dst" "export GOODBYE=farewell"
assert_file_contains "$WORK/dst" "alias ..='cd ..'"
assert_green_contains "  + .bashrc block updated"
# Verify ordering: HELLO before markers, GOODBYE after
hello_ln="$(grep -n 'export HELLO=world' "$WORK/dst" | head -1 | cut -d: -f1)"
marker_start_ln="$(grep -n "$BASH_MARKER_START" "$WORK/dst" | head -1 | cut -d: -f1)"
marker_end_ln="$(grep -n "$BASH_MARKER_END" "$WORK/dst" | head -1 | cut -d: -f1)"
goodbye_ln="$(grep -n 'export GOODBYE=farewell' "$WORK/dst" | head -1 | cut -d: -f1)"
if [ "$hello_ln" -lt "$marker_start_ln" ] && [ "$marker_end_ln" -lt "$goodbye_ln" ]; then
	pass=$((pass + 1))
else
	fail=$((fail + 1))
	echo "  FAIL: user content ordering broken" >&2
fi
result "user content before and after"

# --- CRLF handling -------------------------------------------------
# Input:  src has CRLF line endings.  dst has LF content.
# Expect: merged content is LF-only, no \r in dst.
check
printf 'alias ll=ls -alF\r\nalias la=ls -A\r\n' >"$WORK/src"
printf 'export MY_VAR=42\n' >"$WORK/dst"
reset_calls
merge_bashrc "$WORK/src" "$WORK/dst"
assert_no_cr "$WORK/dst"
assert_file_contains "$WORK/dst" "export MY_VAR=42"
assert_file_contains "$WORK/dst" "alias ll=ls -alF"
assert_file_contains "$WORK/dst" "alias la=ls -A"
result "CRLF handling"

# --- idempotency ---------------------------------------------------
# Input:  dst has managed block with same content as src.
# Action: run merge_bashrc TWICE.
# Expect: second run says "up to date", dst unchanged.
check
cat >"$WORK/src" <<'EOF'
alias ll='ls -alF'
alias la='ls -A'
EOF
{
	printf 'export MY_VAR=42\n\n'
	printf '%s\n' "$BASH_MARKER_START"
	printf "alias ll='ls -alF'\nalias la='ls -A'\n"
	printf '%s\n' "$BASH_MARKER_END"
} >"$WORK/dst"
reset_calls
merge_bashrc "$WORK/src" "$WORK/dst" >/dev/null
dst_after_first="$(cat "$WORK/dst")"
reset_calls
merge_bashrc "$WORK/src" "$WORK/dst"
dst_after_second="$(cat "$WORK/dst")"
assert_green_contains "  (up to date)"
if [ "$dst_after_first" = "$dst_after_second" ]; then
	pass=$((pass + 1))
else
	fail=$((fail + 1))
	echo "  FAIL: dst changed after second run" >&2
fi
result "idempotency"

finish
