# merge_gitconfig <src>
#
# ── Algorithm ──
#
#   1. Parse <src> (a .gitconfig file) using git config --file --list.
#      This outputs flat "section.key=value" lines, one per key.
#      Git's own INI parser handles sections, subsections, quoting,
#      line-continuation, includes — no text-mode regex hacking.
#
#   2. For each key=value pair from the repo file:
#      a) Strip \r and trim whitespace (defence against CRLF / odd formatting).
#      b) Query the user's global config: git config --global --get <key>
#      c) Three-way decision:
#           - Key NOT set globally  →  git config --global <key> <value>  (add)
#           - Key set, same value   →  skip (already present)
#           - Key set, DIFF value   →  skip, report conflict (user wins)
#
# Requires: green(), dim(), yellow() helpers; git on PATH.
# Returns: 0 on success, 1 if <src> is missing.
merge_gitconfig() {
	local src="$1"
	local added=0 skipped=0 conflicts=0
	local key value existing

	if [ ! -f "$src" ]; then
		echo "  ERROR: source file not found: $src" >&2
		return 1
	fi

	# ── git config --file --list: git's own parser ──
	# Produces lines like "core.autocrlf=input" — no section headers,
	# no indentation, just canonical key=value pairs.
	while IFS='=' read -r key value || [ -n "$key" ]; do
		[ -z "$key" ] && continue

		# Defensive: strip CR and trim surrounding whitespace.
		# git config output is normally clean, but CRLF checkouts or
		# unusual config values could introduce artifacts.
		key="${key%$'\r'}"
		key="${key#"${key%%[![:space:]]*}"}"
		key="${key%"${key##*[![:space:]]}"}"
		value="${value%$'\r'}"
		value="${value#"${value%%[![:space:]]*}"}"
		value="${value%"${value##*[![:space:]]}"}"

		# Query the user's current global setting for this key
		existing="$(git config --global --get "$key" 2>/dev/null || true)"

		# ── Three-way merge decision ──
		if [ -z "$existing" ]; then
			# Key not set → safe to add the repo default
			git config --global "$key" "$value"
			green "  + ${key} = ${value}"
			added=$((added + 1))
		elif [ "$existing" = "$value" ]; then
			# Already set to the same value → nothing to do
			dim "  = ${key} = ${value}"
			skipped=$((skipped + 1))
		else
			# Set to a different value → user wins, report conflict
			yellow "  ~ ${key} = ${value}  (you have: ${existing} — kept yours)"
			conflicts=$((conflicts + 1))
		fi
	done < <(git config --file "$src" --list 2>/dev/null || true)

	if [ "$added" -eq 0 ] && [ "$conflicts" -eq 0 ]; then
		green "  (all keys already present)"
	elif [ "$added" -gt 0 ] || [ "$conflicts" -gt 0 ]; then
		green "  ${added} key(s) added, ${skipped} already present, ${conflicts} conflict(s) kept as-is"
	fi
	return 0
}
