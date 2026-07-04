#!/usr/bin/env bash
# Unit tests for lib/merge-gitignore.sh
#
# merge_gitignore compares src and dst line by line.  Tests run in
# an isolated temp directory (cleaned via trap EXIT) so file state
# is explicit per case — each case overwrites src / dst as needed.
#
# Cases:
#   1. src missing          — error path
#   2. dst does not exist   — first install, all patterns added
#   3. partial overlap      — some "=", some "+", custom patterns kept
#   4. all already present  — everything "="
#   5. blanks & comments    — empty / # lines skipped
#   6. CRLF handling        — \r stripped, dst stays LF
#   7. idempotency          — second run all "=", no duplicates
#   8. negation pattern     — !important.log treated as literal
set -euo pipefail

source "$(dirname "$0")/helpers.sh"

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
source "$(dirname "$0")/../lib/merge-gitignore.sh"

# --- src missing --------------------------------------------------
# Input:  nonexistent src path.
# Expect: return 1, no files created.
check
if merge_gitignore "/nonexistent/src" "/tmp/dst" 2>/dev/null; then
	fail=$((fail + 1))
	echo "  FAIL: expected non-zero exit" >&2
else
	pass=$((pass + 1))
fi
result "src missing"

# --- dst does not exist -------------------------------------------
# Input:  src has .history, _bmad*, .claude.  dst does not exist.
# Expect: dst created as copy of src.  All patterns reported as "+".
check
WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT
cat >"$WORK/src" <<'EOF'
.history
_bmad*
.claude
EOF
reset_calls
merge_gitignore "$WORK/src" "$WORK/dst"
assert_file_contains "$WORK/dst" ".history"
assert_file_contains "$WORK/dst" "_bmad*"
assert_file_contains "$WORK/dst" ".claude"
assert_green_contains "  + .history"
assert_green_contains "  + _bmad*"
assert_green_contains "  + .claude"
result "dst does not exist"

# --- partial overlap ----------------------------------------------
# Input:  src has .history, .vscode, _bmad*.
#         dst has .history (overlap) + .mycustom (user-only).
# Expect: .history → "=", .vscode + _bmad* → "+", .mycustom untouched.
check
cat >"$WORK/src" <<'EOF'
.history
.vscode
_bmad*
EOF
printf '.history\n.mycustom\n' >"$WORK/dst"
reset_calls
merge_gitignore "$WORK/src" "$WORK/dst"
assert_file_contains "$WORK/dst" ".history"
assert_file_contains "$WORK/dst" ".vscode"
assert_file_contains "$WORK/dst" "_bmad*"
assert_file_contains "$WORK/dst" ".mycustom"
assert_dim_contains "  = .history"
assert_green_contains "  + .vscode"
assert_green_contains "  + _bmad*"
result "partial overlap"

# --- all already present ------------------------------------------
# Input:  src has .history, _bmad*.  dst has both + .mycustom.
# Expect: Both "=", .mycustom untouched, no new lines appended.
check
cat >"$WORK/src" <<'EOF'
.history
_bmad*
EOF
printf '.history\n_bmad*\n.mycustom\n' >"$WORK/dst"
reset_calls
merge_gitignore "$WORK/src" "$WORK/dst"
assert_dim_contains "  = .history"
assert_dim_contains "  = _bmad*"
assert_file_contains "$WORK/dst" ".mycustom"
result "all already present"

# --- skip blanks and comments -------------------------------------
# Input:  src has comments, blank lines, and two actual patterns.
#         dst is empty (but exists — triggers merge path).
# Expect: Only .history and _bmad* end up in dst.  No comment text.
check
cat >"$WORK/src" <<'EOF'
# This is a comment
.history

_bmad*
# Another comment
EOF
printf '' >"$WORK/dst"
reset_calls
merge_gitignore "$WORK/src" "$WORK/dst"
assert_file_contains "$WORK/dst" ".history"
assert_file_contains "$WORK/dst" "_bmad*"
assert_file_not_contains "$WORK/dst" "# This is a comment"
assert_green_contains "  + .history"
assert_green_contains "  + _bmad*"
for call in "${GREEN_CALLS[@]}"; do
	if [[ "$call" == *"#"* ]]; then
		fail=$((fail + 1))
		echo "  FAIL: comment was not skipped: $call" >&2
	fi
done
result "skip blanks and comments"

# --- CRLF handling ------------------------------------------------
# Input:  src has CRLF endings.  dst has LF .history.
# Expect: .history matches despite \r → "=".  _bmad* → "+".
#         dst file contains NO \r after merge.
# Why:    Windows/WSL git may checkout with CRLF.
check
printf '.history\r\n_bmad*\r\n' >"$WORK/src"
printf '.history\n' >"$WORK/dst"
reset_calls
merge_gitignore "$WORK/src" "$WORK/dst"
assert_dim_contains "  = .history"
assert_green_contains "  + _bmad*"
assert_file_contains "$WORK/dst" "_bmad*"
if grep -q $'\r' "$WORK/dst"; then
	fail=$((fail + 1))
	echo "  FAIL: CR found in dst file" >&2
else
	pass=$((pass + 1))
fi
result "CRLF handling"

# --- idempotency --------------------------------------------------
# Input:  src has .history, .claude.  dst has .history, .mycustom.
# Step 1: first run — .claude added.  Step 2: second run — all "=".
# Expect: no duplicates, .mycustom still there.
check
cat >"$WORK/src" <<'EOF'
.history
.claude
EOF
printf '.history\n.mycustom\n' >"$WORK/dst"
reset_calls
merge_gitignore "$WORK/src" "$WORK/dst" >/dev/null
reset_calls
merge_gitignore "$WORK/src" "$WORK/dst"
assert_dim_contains "  = .history"
assert_dim_contains "  = .claude"
assert_file_contains "$WORK/dst" ".mycustom"
history_count=$(grep -cFx '.history' "$WORK/dst" || true)
claude_count=$(grep -cFx '.claude' "$WORK/dst" || true)
if [ "$history_count" -eq 1 ] && [ "$claude_count" -eq 1 ]; then
	pass=$((pass + 1))
else
	fail=$((fail + 1))
	echo "  FAIL: duplicates — .history:${history_count}, .claude:${claude_count}" >&2
fi
result "idempotency"

# --- negation pattern ---------------------------------------------
# Input:  src has *.log and !important.log.  dst has *.log.
# Expect: *.log → "=", !important.log → "+".
# Why:    grep -F treats "!" as literal, not regex negation.
check
cat >"$WORK/src" <<'EOF'
*.log
!important.log
EOF
printf '*.log\n' >"$WORK/dst"
reset_calls
merge_gitignore "$WORK/src" "$WORK/dst"
assert_dim_contains "  = *.log"
assert_green_contains "  + !important.log"
assert_file_contains "$WORK/dst" "!important.log"
result "negation pattern"

finish
