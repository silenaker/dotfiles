# merge_bashrc <src> <dst>
#
# ── Algorithm ──
#
#   Managed-block merge with sentinel markers:
#
#       # >>> dotfiles .bashrc >>>
#       ... managed content from repo ...
#       # <<< dotfiles .bashrc <<<
#
#   1. If <dst> does not exist:
#        Copy <src> to <dst> as-is (first-install path).
#
#   2. If <dst> exists and contains the markers:
#        Replace everything between (and including) the markers
#        with the current <src> content wrapped in fresh markers.
#        If the new content matches what is already between the
#        markers, skip — nothing to do.
#
#   3. If <dst> exists but does NOT contain the markers:
#        Append the <src> content wrapped in markers.
#        An extra blank line is inserted before the block so
#        the user's existing content and the managed block are
#        visually separated.
#
#   This strategy is safe: user customisation above or below the
#   managed block is never touched.  The user can freely add
#   aliases, exports, or source commands outside the markers.
#
# Requires: green(), dim() helpers; sed, grep, head, tail on PATH.
# Returns: 0 on success, 1 if <src> is missing.
merge_bashrc() {
	local src="$1" dst="$2"
	local start_marker="# >>> dotfiles .bashrc >>>"
	local end_marker="# <<< dotfiles .bashrc <<<"

	if [ ! -f "$src" ]; then
		echo "  ERROR: source file not found: $src" >&2
		return 1
	fi

	# ── Normalise src content (strip CR) ──
	local src_content
	src_content="$(sed 's/\r$//' "$src")"

	# ── First-install path: dst does not exist ──
	# Wrap content in sentinel markers so subsequent runs recognise the
	# managed block and enter the replace path (not the append path).
	if [ ! -f "$dst" ]; then
		{
			printf '%s\n' "$start_marker"
			printf '%s\n' "$src_content"
			printf '%s\n' "$end_marker"
		} >"$dst"
		green "  + .bashrc (created)"
		local added=0 line
		while IFS= read -r line || [ -n "$line" ]; do
			line="${line%$'\r'}"
			[[ -z "$line" || "$line" == \#* ]] && continue
			added=$((added + 1))
		done <<<"$src_content"
		green "  ${added} active line(s) installed"
		return 0
	fi

	# ── dst has markers: replace the managed block ──
	# Normalise line endings for reliable marker detection — CRLF
	# (from Windows editors) would otherwise defeat grep -xF.
	# Use a here-string (<<<) rather than process substitution
	# because /dev/fd redirection is unreliable on some platforms (WSL).
	local dst_norm
	dst_norm="$(sed 's/\r$//' "$dst")"
	if grep -qxF "$start_marker" <<<"$dst_norm" 2>/dev/null && \
	   grep -qxF "$end_marker" <<<"$dst_norm" 2>/dev/null; then
		local start_ln end_ln
		start_ln="$(grep -nxF "$start_marker" <<<"$dst_norm" | head -1 | cut -d: -f1)"
		end_ln="$(grep -nxF "$end_marker" <<<"$dst_norm" | head -1 | cut -d: -f1)"

		if [ -n "$start_ln" ] && [ -n "$end_ln" ] && [ "$start_ln" -lt "$end_ln" ]; then
			# Extract current block content (between markers, exclusive).
			# Strip CR so comparison works when dst has CRLF endings.
			local old_content
			old_content="$(sed -n "$((start_ln + 1)),$((end_ln - 1))p" "$dst" | sed 's/\r$//')"

			if [ "$old_content" = "$src_content" ]; then
				green "  (up to date)"
				return 0
			fi

			# Replace: lines before start + new block + lines after end.
			# Normalise CRLF from preserved user sections for consistent
			# LF-only output (prevents mixed line endings).
			{
				head -n $((start_ln - 1)) "$dst" | sed 's/\r$//'
				printf '%s\n' "$start_marker"
				printf '%s\n' "$src_content"
				printf '%s\n' "$end_marker"
				tail -n +$((end_ln + 1)) "$dst" | sed 's/\r$//'
			} >"${dst}.tmp"
			mv "${dst}.tmp" "$dst"
			green "  + .bashrc block updated"
			return 0
		fi
	fi

	# ── dst exists, no (valid) markers: append managed block ──
	{
		cat "$dst"
		printf '\n%s\n' "$start_marker"
		printf '%s\n' "$src_content"
		printf '%s\n' "$end_marker"
	} >"${dst}.tmp"
	mv "${dst}.tmp" "$dst"
	green "  + .bashrc block appended"
	return 0
}
