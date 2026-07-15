#!/usr/bin/env bash
# Integration test for bootstrap.sh
#
# Verifies the assembled bootstrap.sh end-to-end in an isolated $HOME.
# Uses a local file:// clone so no network is required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP="$ROOT/bootstrap.sh"
REPO_URL="file://$ROOT/.git"

source "$(dirname "$0")/helpers.sh"
source "$(dirname "$0")/../lib/constants.sh"

# ------------------------------------------------------------------
if [ ! -x "$BOOTSTRAP" ]; then
	echo "  ERROR: bootstrap.sh not found — run build.sh first" >&2
	exit 1
fi

# --- clean install ------------------------------------------------
# State:  $HOME has no pre-existing dotfiles.
# Action: run bootstrap.sh.
# Expect: dotfiles installed from repo, no CRLF.
check
TESTHOME="$(mktemp -d)"
export HOME="$TESTHOME"
DOTFILES_REPO_URL="$REPO_URL" bash "$BOOTSTRAP" >/dev/null 2>&1
assert_git_config "core.autocrlf" "input"
assert_git_config "core.excludesfile" "~/.gitignore_global"
ignore_path="$HOME/.gitignore_global"
assert_file_contains "$ignore_path" ".history"
assert_file_contains "$ignore_path" "_bmad*"
assert_file_contains "$ignore_path" ".claude"
assert_file_contains "$ignore_path" ".agents"
assert_file_contains "$ignore_path" ".understand-anything"
assert_no_cr "$ignore_path"
assert_file_contains "$HOME/.bashrc" "HISTSIZE=10000"
assert_file_contains "$HOME/.bashrc" "alias ll='ls -alF'"
assert_no_cr "$HOME/.bashrc"
rm -rf "$TESTHOME"
result "clean install"

# --- merge with existing dotfiles ---------------------------------
# State:  pre-existing dotfiles with partial overlap and conflicts.
# Expect: conflicts keep user values, overlaps not duplicated,
#         new entries added, user-only entries untouched.
check
TESTHOME="$(mktemp -d)"
export HOME="$TESTHOME"
ignore_path_tilde="~/.test_gitignore"
ignore_path_abs="$HOME/.test_gitignore"
git config --global user.name "Real User"
git config --global core.autocrlf true
git config --global core.excludesFile "$ignore_path_tilde"
printf '.history\n.mycustom\n' >"$ignore_path_abs"
printf 'export MY_CUSTOM=keep-me\n' >"$HOME/.bashrc"
DOTFILES_REPO_URL="$REPO_URL" bash "$BOOTSTRAP" >/dev/null 2>&1
assert_git_config "user.name" "Real User"
assert_git_config "core.autocrlf" "true"
assert_git_config "core.excludesfile" "$ignore_path_tilde"
assert_file_contains "$ignore_path_abs" ".history"
assert_unique "$ignore_path_abs" ".history"
assert_file_contains "$ignore_path_abs" ".mycustom"
assert_file_contains "$ignore_path_abs" "_bmad*"
assert_file_contains "$ignore_path_abs" ".claude"
assert_no_cr "$ignore_path_abs"
assert_file_contains "$HOME/.bashrc" "export MY_CUSTOM=keep-me"
assert_file_contains "$HOME/.bashrc" "$BASH_MARKER_START"
assert_file_contains "$HOME/.bashrc" "HISTSIZE=10000"
assert_file_contains "$HOME/.bashrc" "$BASH_MARKER_END"
assert_no_cr "$HOME/.bashrc"
rm -rf "$TESTHOME"
result "merge with existing dotfiles"

# --- idempotency --------------------------------------------------
# State:  pre-existing dotfiles with partial overlap.
# Action: run bootstrap.sh TWICE.
# Expect: byte-for-byte identical files after both runs.
check
TESTHOME="$(mktemp -d)"
export HOME="$TESTHOME"
ignore_path="$HOME/.test_gitignore"
git config --global user.name "Real User"
git config --global core.autocrlf true
git config --global core.excludesFile "$ignore_path"
printf '.history\n' >"$ignore_path"
DOTFILES_REPO_URL="$REPO_URL" bash "$BOOTSTRAP" >/dev/null 2>&1
gitconfig_after_first=$(cat "$HOME/.gitconfig")
gitignore_after_first=$(cat "$ignore_path")
bashrc_after_first=$(cat "$HOME/.bashrc")
DOTFILES_REPO_URL="$REPO_URL" bash "$BOOTSTRAP" >/dev/null 2>&1
assert_git_config "core.autocrlf" "true"
assert_unique "$ignore_path" ".history"
if [ "$(cat "$HOME/.gitconfig")" = "$gitconfig_after_first" ]; then
	pass=$((pass + 1))
else
	fail=$((fail + 1))
	echo "  FAIL: .gitconfig changed after second run" >&2
fi
if [ "$(cat "$ignore_path")" = "$gitignore_after_first" ]; then
	pass=$((pass + 1))
else
	fail=$((fail + 1))
	echo "  FAIL: gitignore changed after second run" >&2
fi
if [ "$(cat "$HOME/.bashrc")" = "$bashrc_after_first" ]; then
	pass=$((pass + 1))
else
	fail=$((fail + 1))
	echo "  FAIL: .bashrc changed after second run" >&2
fi
rm -rf "$TESTHOME"
result "idempotency"

finish
