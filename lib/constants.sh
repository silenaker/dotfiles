# Shared constants for dotfiles merge modules and tests.
#
# This file is sourced (not executed).  It has no shebang so that
# build.sh can inline it directly into bootstrap.sh via emit_file,
# where it runs as top-level code before the merge functions.

# --- .bashrc managed-block markers ---
BASH_MARKER_START='# >>> dotfiles .bashrc >>>'
BASH_MARKER_END='# <<< dotfiles .bashrc <<<'
