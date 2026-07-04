#!/usr/bin/env bash
# Unit tests for lib/merge-gitconfig.sh
#
# git config --global reads/writes ~/.gitconfig.  To isolate tests
# we point $HOME at a temp directory.  The trap on EXIT restores
# the real HOME and cleans up.  All tests share one sandbox $HOME
# so state accumulates — this mirrors real-world cumulative config.
#
# Cases:
#   1. src missing               — error path
#   2. adds keys to empty config — not set → all "+"
#   3. skips already-set keys    — same value → "="
#   4. conflict, user wins       — different value → "~", user kept
#   5. mixed add/skip/conflict   — all three outcomes in one run
#   6. idempotency               — second run same results
set -euo pipefail

source "$(dirname "$0")/helpers.sh"

# ------------------------------------------------------------------
# Stub helpers
# ------------------------------------------------------------------
GREEN_CALLS=()
DIM_CALLS=()
YELLOW_CALLS=()
green() { GREEN_CALLS+=("$*"); }
dim() { DIM_CALLS+=("$*"); }
yellow() { YELLOW_CALLS+=("$*"); }
reset_calls() {
	GREEN_CALLS=()
	DIM_CALLS=()
	YELLOW_CALLS=()
}

assert_green_contains() { assert_call_contains GREEN_CALLS "$1" "green"; }
assert_dim_contains() { assert_call_contains DIM_CALLS "$1" "dim"; }
assert_yellow_contains() { assert_call_contains YELLOW_CALLS "$1" "yellow"; }

# ------------------------------------------------------------------
# Sandbox
# ------------------------------------------------------------------
REAL_HOME="$HOME"
TESTHOME="$(mktemp -d)"
export HOME="$TESTHOME"
trap "export HOME='$REAL_HOME'; rm -rf '$TESTHOME'" EXIT

# Init: empty value → treated as "not set" by [ -z ].
git config --global user.name ""

# ------------------------------------------------------------------
source "$(dirname "$0")/../lib/merge-gitconfig.sh"

# --- src missing --------------------------------------------------
# Input:  nonexistent src path.
# Expect: return 1.
check
if merge_gitconfig "/nonexistent/src" 2>/dev/null; then
	fail=$((fail + 1))
	echo "  FAIL: expected non-zero exit" >&2
else
	pass=$((pass + 1))
fi
result "src missing"

# --- adds keys to empty config ------------------------------------
# State:  global config has only user.name="" (treated as unset).
#         Repo src has core.autocrlf + core.excludesfile.
# Expect: Both keys → "+", git config returns the set values.
check
WORK="$(mktemp -d)"
cat >"$WORK/src" <<'EOF'
[core]
	autocrlf = input
	excludesfile = ~/.gitignore_global
EOF
reset_calls
merge_gitconfig "$WORK/src"
assert_git_config "core.autocrlf" "input"
assert_git_config "core.excludesfile" "~/.gitignore_global"
assert_green_contains "  + core.autocrlf = input"
assert_green_contains "  + core.excludesfile = ~/.gitignore_global"
rm -rf "$WORK"
result "adds keys to empty config"

# --- skips already-set keys ---------------------------------------
# State:  core.autocrlf pre-set to "input" (same as repo).
# Expect: "=" — already present, no write.
check
WORK="$(mktemp -d)"
cat >"$WORK/src" <<'EOF'
[core]
	autocrlf = input
EOF
git config --global core.autocrlf input
reset_calls
merge_gitconfig "$WORK/src"
assert_git_config "core.autocrlf" "input"
assert_dim_contains "  = core.autocrlf = input"
rm -rf "$WORK"
result "skips already-set keys"

# --- conflict, user value wins ------------------------------------
# State:  core.autocrlf pre-set to "true" (repo wants "input").
# Expect: "~" — conflict reported, user's "true" preserved.
check
WORK="$(mktemp -d)"
cat >"$WORK/src" <<'EOF'
[core]
	autocrlf = input
EOF
git config --global core.autocrlf true
reset_calls
merge_gitconfig "$WORK/src"
assert_git_config "core.autocrlf" "true"
assert_yellow_contains "  ~ core.autocrlf = input  (you have: true — kept yours)"
rm -rf "$WORK"
result "conflict — user value wins"

# --- mixed add / skip / conflict ----------------------------------
# State:  core.excludesfile pre-set to match → skip.
#         core.autocrlf pre-set to different → conflict.
#         user.name not set (empty from init) → add.
# Expect: One "=", one "~", one "+".
check
WORK="$(mktemp -d)"
cat >"$WORK/src" <<'EOF'
[core]
	autocrlf = input
	excludesfile = ~/.gitignore_global
[user]
	name = Dotfiles User
EOF
git config --global core.excludesfile '~/.gitignore_global'
git config --global core.autocrlf true
reset_calls
merge_gitconfig "$WORK/src"
assert_git_config "core.excludesfile" "~/.gitignore_global"
assert_git_config "core.autocrlf" "true"
assert_git_config "user.name" "Dotfiles User"
assert_dim_contains "  = core.excludesfile = ~/.gitignore_global"
assert_yellow_contains "  ~ core.autocrlf = input  (you have: true — kept yours)"
assert_green_contains "  + user.name = Dotfiles User"
rm -rf "$WORK"
result "mixed add / skip / conflict"

# --- idempotency --------------------------------------------------
# State:  core.autocrlf conflict, core.excludesfile match.
# Step 1: first run (output discarded).  Step 2: second run.
# Expect: same "~" and "=", values unchanged.
check
WORK="$(mktemp -d)"
cat >"$WORK/src" <<'EOF'
[core]
	autocrlf = input
	excludesfile = ~/.gitignore_global
EOF
git config --global core.autocrlf true
git config --global core.excludesfile '~/.gitignore_global'
reset_calls
merge_gitconfig "$WORK/src" >/dev/null
reset_calls
merge_gitconfig "$WORK/src"
assert_yellow_contains "  ~ core.autocrlf = input  (you have: true — kept yours)"
assert_dim_contains "  = core.excludesfile = ~/.gitignore_global"
assert_git_config "core.autocrlf" "true"
assert_git_config "core.excludesfile" "~/.gitignore_global"
rm -rf "$WORK"
result "idempotency"

finish
