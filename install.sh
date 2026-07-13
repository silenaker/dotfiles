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
# .bashrc
# ------------------------------------------------------------------
if [ -f "$DOTFILES_DIR/.bashrc" ]; then
	# Guard against self-referencing symlink when DOTFILES_DIR == HOME.
	if [ "$DOTFILES_DIR" = "$HOME" ]; then
		echo "  WARNING: DOTFILES_DIR equals HOME, skipping .bashrc symlink" >&2
	else
		# Back up any pre-existing regular file before replacing it.
		if [ -f "$HOME/.bashrc" ] && [ ! -L "$HOME/.bashrc" ]; then
			cp "$HOME/.bashrc" "$HOME/.bashrc.bak"
			echo "  (backed up existing .bashrc to .bashrc.bak)"
		fi
		ln -sf "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
		echo "✓ .bashrc"
	fi
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
