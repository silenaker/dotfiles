#!/usr/bin/env bash
# DevContainer dotfiles installer
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Installing dotfiles from $DOTFILES_DIR"

# ------------------------------------------------------------------
# .gitignore_global
# ------------------------------------------------------------------
if [ -f "$DOTFILES_DIR/.gitignore_global" ]; then
	ln -sf "$DOTFILES_DIR/.gitignore_global" "$HOME/.gitignore_global"
	echo "✓ .gitignore_global"
fi

# ------------------------------------------------------------------
# .gitconfig
#
# DevContainers often pre-populate $HOME/.gitconfig with
# user.name / user.email from container env vars.  We want to
# keep those while also applying our own defaults (autocrlf,
# excludesfile, etc.).  Use git's [include] mechanism:
#
#   Our dotfiles .gitconfig is the included "base" config.
#   The container's top-level file provides overrides.
# ------------------------------------------------------------------
if [ -f "$DOTFILES_DIR/.gitconfig" ]; then
	if [ -f "$HOME/.gitconfig" ]; then
		{
			echo "[include]"
			echo "	path = $DOTFILES_DIR/.gitconfig"
			echo ""
			cat "$HOME/.gitconfig"
		} > "$HOME/.gitconfig.tmp"
		mv "$HOME/.gitconfig.tmp" "$HOME/.gitconfig"
	else
		ln -sf "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
	fi
	echo "✓ .gitconfig"
fi

echo ""
echo "Dotfiles installation complete."
