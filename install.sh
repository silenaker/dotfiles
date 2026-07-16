#!/usr/bin/env bash
# DevContainer dotfiles installer
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Installing dotfiles from $DOTFILES_DIR"

# ------------------------------------------------------------------
# .bashrc
# ------------------------------------------------------------------
SOURCE_LINE="source \"$DOTFILES_DIR/.bashrc\""
if [ -f "$HOME/.bashrc" ]; then
	if ! grep -qF "$SOURCE_LINE" "$HOME/.bashrc" 2>/dev/null; then
		echo "$SOURCE_LINE" >>"$HOME/.bashrc"
	fi
else
	echo "$SOURCE_LINE" >"$HOME/.bashrc"
fi
echo "✓ .bashrc"

# ------------------------------------------------------------------
# .gitconfig
# ------------------------------------------------------------------
git config --global include.path "$DOTFILES_DIR/.gitconfig"
git config --global core.excludesFile "$DOTFILES_DIR/.gitignore_global"
echo "✓ .gitconfig"

echo ""
echo "Dotfiles installation complete."
