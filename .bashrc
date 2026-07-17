# ~/.bashrc — silenaker dotfiles
#
# This file is managed by the dotfiles bootstrap installer.
# See: https://github.com/silenaker/dotfiles

# ------------------------------------------------------------------
# History
# ------------------------------------------------------------------
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend

# ------------------------------------------------------------------
# Shell options
# ------------------------------------------------------------------
shopt -s checkwinsize
shopt -s cdspell
shopt -s dirspell
shopt -s autocd

# ------------------------------------------------------------------
# PATH
# ------------------------------------------------------------------
case ":${PATH}:" in
*:"$HOME/.local/bin":*)
	;;
*)
	# Prepending path in case a system-installed binary needs to be overridden
	export PATH="$HOME/.local/bin:$PATH"
	;;
esac

# ------------------------------------------------------------------
# Aliases
# ------------------------------------------------------------------
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# Safety nets
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'

# ------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------

# _fztype_match -- fuzzy match: all chars of $1 appear in $2 in order.
_fztype_match() {
	local pattern="$1" target="$2"
	local i=0 j=0 plen=${#pattern} tlen=${#target}
	while ((i < plen && j < tlen)); do
		if [ "${pattern:i:1}" = "${target:j:1}" ]; then
			((i++))
		fi
		((j++))
	done
	((i == plen))
}

# _fztype_filter -- fuzzy filter stdin lines against $1, appending matches to nameref $2.
_fztype_filter() {
	local term="$1" cmd
	local -n _result="$2"
	while IFS= read -r cmd; do
		_fztype_match "$term" "$cmd" && _result+=("$cmd")
	done
}

# _fztype_cache_write -- atomically write $1 to the command cache in background.
_fztype_cache_write() {
	_fztype_log "INFO" "cache_write: spawning background write"
	(
		d="${XDG_CACHE_HOME:-$HOME/.cache}/fztype"
		mkdir -p "$d"
		_fztype_log_file "INFO" "cache_write: writing $(echo "$1" | wc -l) entries"
		export -f _fztype_log_file
		export d
		bash -c '
			set -e
			flock -n 3 || {
				_fztype_log_file "WARN" "cache_write: flock failed (contended)"
				exit 0
			}
			printf "%s\n" "$1" >"$d/commands.tmp"
			mv "$d/commands.tmp" "$d/commands"
			_fztype_log_file "INFO" "cache_write: done"
		' _ "$1" 3>"$d/.lock" >/dev/null 2>>"$d/error.log" &
	) &>/dev/null
}

# _fztype_cache_refresh -- regenerate the command cache from compgen in background.
_fztype_cache_refresh() {
	_fztype_log "INFO" "cache_refresh: spawning background refresh"
	(
		d="${XDG_CACHE_HOME:-$HOME/.cache}/fztype"
		mkdir -p "$d"
		export -f _fztype_log_file
		export d
		bash -c '
			set -e
			flock -n 3 || {
				_fztype_log_file "WARN" "cache_refresh: flock failed (contended)"
				exit 0
			}
			compgen -c | sort -u >"$d/commands.tmp"
			mv "$d/commands.tmp" "$d/commands"
			_fztype_log_file "INFO" "cache_refresh: done ($(wc -l <"$d/commands") entries)"
		' 3>"$d/.lock" >/dev/null 2>>"$d/error.log" &
	) &>/dev/null
}

# _fztype_log -- conditionally log to stderr when FZTYPE_DEBUG is set.
_fztype_log() {
	[ -n "${FZTYPE_DEBUG:-}" ] || return 0
	local level="$1" msg="$2" ts
	ts=$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null) || true
	printf '[%s] [fztype] %-7s %s\n' "${ts:-n/a}" "$level" "$msg" >&2
}

# _fztype_log_file -- log to a file (for backgrounded subshells where stderr is captured).
# WARN/ERROR always write to error.log; INFO writes to debug.log only when FZTYPE_DEBUG is set.
_fztype_log_file() {
	local level="$1" msg="$2"
	local d="${XDG_CACHE_HOME:-$HOME/.cache}/fztype" ts logfile
	mkdir -p "$d"
	ts=$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null) || true
	case "$level" in
	ERROR)
		logfile="$d/error.log"
		;;
	*)
		[ -n "${FZTYPE_DEBUG:-}" ] || return 0
		logfile="$d/debug.log"
		;;
	esac
	printf '[%s] [fztype] %-7s %s\n' "${ts:-n/a}" "$level" "$msg" >>"$logfile"
}

# fztype -- fuzzy command lookup.
# Usage: fztype [-p|--prefix] [-r|--refresh] [-t|--type <type>] <command>
#
# Modes:
#   (default)  Cached non-prefix fuzzy: reads from ~/.cache/fztype/commands,
#              spawns background refresh if cache predates today 00:00.
#              Falls back to -r behavior when cache is missing or empty.
#   -p         Prefix real-time fuzzy: compgen -c <first-char>, no cache I/O.
#              Same matching strategy as the original fztype.
#   -r         Non-prefix real-time fuzzy: compgen -c (all commands), fuzzy
#              filter, then atomically update cache in background.
#   -t         Filter output by command type: alias, function, builtin,
#              keyword, or file.
#
# All modes fuzzy-filter via _fztype_match (subsequence, order-preserving).
fztype() {
	local mode="default" term="" type_filter="" _prev_opt=""

	# Parse flags
	while [[ "${1:-}" == -* ]]; do
		case "$1" in
		-p | --prefix)
			[ "$mode" = "refresh" ] && {
				echo "fztype: options '$_prev_opt' and '$1' cannot be used together" >&2
				return 1
			}
			mode="prefix"
			_prev_opt="$1"
			shift
			;;
		-r | --refresh)
			[ "$mode" = "prefix" ] && {
				echo "fztype: options '$_prev_opt' and '$1' cannot be used together" >&2
				return 1
			}
			mode="refresh"
			_prev_opt="$1"
			shift
			;;
		-t | --type)
			type_filter="$2"
			shift 2
			;;
		--)
			shift
			break
			;;
		*) break ;;
		esac
	done

	term="${1:-}"
	if [ -z "$term" ]; then
		cat >&2 <<'EOF'
Usage: fztype [OPTIONS] <command>

Options:
  -p, --prefix          Prefix fuzzy match (anchored at first character)
  -r, --refresh         Bypass and rebuild the command cache
  -t, --type TYPE       Filter by type: alias, function, builtin, keyword, file
EOF
		return 1
	fi

	# Validate type filter
	if [ -n "$type_filter" ]; then
		case "$type_filter" in
		alias | function | builtin | keyword | file) ;;
		*)
			echo "fztype: invalid type '${type_filter}'. Valid: alias, function, builtin, keyword, file" >&2
			return 1
			;;
		esac
	fi

	_fztype_log "INFO" "mode=$mode term='$term' type_filter=${type_filter:-none}"

	local CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/fztype"
	local CACHE_FILE="$CACHE_DIR/commands"
	local matches=() raw

	case "$mode" in
	prefix)
		_fztype_log "INFO" "prefix mode: filtering from compgen -c '${term:0:1}'"
		_fztype_filter "$term" matches < <(compgen -c "${term:0:1}" | sort -u)
		_fztype_log "INFO" "prefix mode: ${#matches[@]} matches"
		;;
	refresh)
		_fztype_log "INFO" "refresh mode: running compgen -c (all commands)"
		raw=$(compgen -c | sort -u)
		_fztype_cache_write "$raw"
		_fztype_filter "$term" matches <<<"$raw"
		_fztype_log "INFO" "refresh mode: ${#matches[@]} matches"
		;;
	default)
		if [ -s "$CACHE_FILE" ]; then
			# Check midnight expiry.
			local cache_mtime midnight_ts
			cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
			midnight_ts=$(date -d 'today 00:00' +%s 2>/dev/null || echo 0)
			if [ "$cache_mtime" -lt "$midnight_ts" ] 2>/dev/null; then
				_fztype_log "INFO" "default mode: cache expired (mtime=$cache_mtime < midnight=$midnight_ts), refreshing"
				_fztype_cache_refresh
			else
				_fztype_log "INFO" "default mode: cache fresh (mtime=$cache_mtime)"
			fi
			_fztype_filter "$term" matches <"$CACHE_FILE"
			_fztype_log "INFO" "default mode: ${#matches[@]} matches from cache"
		else
			# No cache -- behave like refresh mode.
			_fztype_log "INFO" "default mode: cache missing, falling back to compgen"
			raw=$(compgen -c | sort -u)
			_fztype_cache_write "$raw"
			_fztype_filter "$term" matches <<<"$raw"
			_fztype_log "INFO" "default mode: ${#matches[@]} matches (fallback)"
		fi
		;;
	esac

	if ((${#matches[@]} == 0)); then
		_fztype_log "WARN" "no matches for term='$term'"
		echo "fztype: no commands matching '${term}'" >&2
		return 1
	fi

	local printed=0 cmd cmd_type path
	for cmd in "${matches[@]}"; do
		cmd_type=$(type -t "$cmd" 2>/dev/null)
		# fallback: non-interactive shells may not report aliases via type -t
		if [ -z "$cmd_type" ] && alias "$cmd" &>/dev/null; then
			cmd_type="alias"
		fi
		if [ -n "$type_filter" ] && [ "$cmd_type" != "$type_filter" ]; then
			continue
		fi
		((printed++))
		if [ "$cmd_type" = "file" ]; then
			path=$(type -p "$cmd" 2>/dev/null)
			printf '%-30s %s\n' "$cmd" "${path:-[not found]}"
		else
			printf '%-30s %s\n' "$cmd" "[${cmd_type:-unknown}]"
		fi
	done

	if ((printed == 0)); then
		_fztype_log "WARN" "type filter '$type_filter' excluded all ${#matches[@]} matches"
		echo "fztype: no commands matching '${term}'" >&2
		return 1
	fi
	_fztype_log "INFO" "printed $printed results"
}

# wman -- open web-based man page.
# Usage: wman [-s <source>] [section] <name>
#
# Sources:
#   man7 (default)  https://man7.org/linux/man-pages/
#   arch            https://man.archlinux.org/
#   ubuntu          https://manpages.ubuntu.com/
#   debian          https://manpages.debian.org/
#
# Section auto-detection:
#   wman 1 ls        → section=1, name=ls
#   wman ls.1        → section=1, name=ls
#   wman ls          → default section 1
wman() {
	local source="man7" name="" section="" url=""

	# Parse options
	while [[ "${1:-}" == -* ]]; do
		case "$1" in
		-h | --help)
			cat >&2 <<'EOF'
Usage: wman [-s source] [section] <name>

Options:
  -s, --source  SRC   Web source: man7 (default), arch, ubuntu, debian
  -h, --help          Show this help message

Examples:
  wman ls                # open ls(1) on man7.org
  wman 5 crontab         # open crontab(5) on man7.org
  wman -s arch ls.1      # open ls(1) on man.archlinux.org
EOF
			return 0
			;;
		-s | --source)
			source="$2"
			shift 2
			;;
		--)
			shift
			break
			;;
		*) break ;;
		esac
	done

	# Validate source early (catches -s with missing/invalid value)
	case "$source" in
	man7 | arch | archlinux | ubuntu | debian) ;;
	*)
		echo "wman: unknown source '${source}'. Valid: man7, arch, ubuntu, debian" >&2
		return 1
		;;
	esac

	# Argument parsing with section auto-detection
	if [ $# -eq 0 ]; then
		cat >&2 <<'EOF'
Usage: wman [-s source] [section] <name>

Options:
  -s, --source  SRC   Web source: man7 (default), arch, ubuntu, debian
  -h, --help          Show this help message

Examples:
  wman ls                # open ls(1) on man7.org
  wman 5 crontab         # open crontab(5) on man7.org
  wman -s arch ls.1      # open ls(1) on man.archlinux.org
EOF
		return 1
	elif [ $# -eq 2 ] && [[ "$1" =~ ^[0-9]+[a-z]*$ ]]; then
		# wman 1 ls
		section="$1"
		name="$2"
	else
		# wman ls or wman ls.1
		name="$1"
		if [[ "$name" =~ ^(.+)\.([0-9]+[a-z]*)$ ]]; then
			name="${BASH_REMATCH[1]}"
			section="${BASH_REMATCH[2]}"
		else
			section="1"
		fi
	fi

	# Warn on extra arguments (likely user error)
	if [ $# -gt 2 ]; then
		echo "wman: ignoring extra arguments after '${name}'" >&2
	elif [ $# -gt 1 ] && ! [[ "$1" =~ ^[0-9]+[a-z]*$ ]]; then
		echo "wman: ignoring extra arguments after '${name}'" >&2
	fi

	# Resolve URL
	case "$source" in
	man7)
		url="https://man7.org/linux/man-pages/man${section}/${name}.${section}.html"
		;;
	arch | archlinux)
		url="https://man.archlinux.org/man/${name}.${section}"
		;;
	ubuntu)
		url="https://manpages.ubuntu.com/manpages/en/man${section}/${name}.${section}.html"
		;;
	debian)
		url="https://manpages.debian.org/${name}.${section}.en.html"
		;;
	esac

	if ! command -v open &>/dev/null; then
		echo "wman: 'open' command not found. Install it or set BROWSER." >&2
		return 1
	fi

	open "$url"
}

# ------------------------------------------------------------------
# Prompt
# ------------------------------------------------------------------
if [ "$TERM" != "dumb" ] && [ -z "${INSIDE_EMACS:-}" ]; then
	case "$(id -u)" in
	0) PS1='\[\033[01;31m\]\h\[\033[01;34m\] \w\[\033[00m\]\$ ' ;; # root: red hostname
	*) PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ ' ;;
	esac
fi

# ------------------------------------------------------------------
# Less colours
# ------------------------------------------------------------------
export LESS=-R
export LESS_TERMCAP_mb=$'\E[1;31m'
export LESS_TERMCAP_md=$'\E[1;36m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_us=$'\E[1;32m'
export LESS_TERMCAP_ue=$'\E[0m'
