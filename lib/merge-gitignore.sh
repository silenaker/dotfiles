# merge_gitignore <src> <dst>
#
# ── Algorithm ──
#
#   for each line in <src>:
#       strip trailing \r                    # CRLF defence
#       skip if empty or starts with #       # blank / comment lines are not patterns
#       if line appears as an exact whole line in <dst>:
#           skip (report "=")                # already present, nothing to do
#       else:
#           append line to <dst>             # missing pattern, add it
#           report "+"
#
#   If <dst> does not exist at all, it is created as a copy of <src>
#   (first-install path: no merging needed).
#
# Requires: green(), dim() helpers (for output).
# Returns: 0 on success, 1 if <src> is missing.
merge_gitignore() {
	local src="$1" dst="$2"
	local added=0 skipped=0 line

	if [ ! -f "$src" ]; then
		echo "  ERROR: source file not found: $src" >&2
		return 1
	fi

	# ── First-install path: dst does not exist ──
	if [ ! -f "$dst" ]; then
		cp "$src" "$dst"
		while IFS= read -r line || [ -n "$line" ]; do
			line="${line%$'\r'}"
			[[ -z "$line" || "$line" == \#* ]] && continue
			green "  + ${line}"
			added=$((added + 1))
		done <"$src"
		green "  ${added} pattern(s) added"
		return 0
	fi

	# ── Merge path: dst exists, compare line by line ──
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%$'\r'}"
		[[ -z "$line" || "$line" == \#* ]] && continue
		# grep -qxF: exact whole-line, fixed-string (see design note #1)
		if grep -qxF "$line" "$dst" 2>/dev/null; then
			dim "  = ${line}"
			skipped=$((skipped + 1))
		else
			echo "$line" >>"$dst"
			green "  + ${line}"
			added=$((added + 1))
		fi
	done <"$src"

	if [ "$added" -eq 0 ]; then
		green "  (all patterns already present)"
	else
		green "  ${added} pattern(s) added, ${skipped} already present"
	fi
	return 0
}
