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

# _fzmatch -- fuzzy match: all chars of $1 appear in $2 in order.
_fzmatch() {
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

# _fzfilter -- fuzzy filter stdin lines against $1, appending matches to nameref $2.
_fzfilter() {
	local term="$1" cmd
	local -n _result="$2"
	while IFS= read -r cmd; do
		_fzmatch "$term" "$cmd" && _result+=("$cmd")
	done
}

# _fzcache_write -- atomically write $1 to the command cache in background.
_fzcache_write() {
	(nohup bash -c '
		d="${XDG_CACHE_HOME:-$HOME/.cache}/fztype"
		mkdir -p "$d" 2>/dev/null || true
		printf "%s\n" "$1" > "$d/commands.tmp" && mv "$d/commands.tmp" "$d/commands"
	' _ "$1" &>/dev/null &) &>/dev/null
}

# _fzcache_refresh -- regenerate the command cache from compgen in background.
_fzcache_refresh() {
	(nohup bash -c '
		d="${XDG_CACHE_HOME:-$HOME/.cache}/fztype"
		mkdir -p "$d" 2>/dev/null || true
		compgen -c | sort -u > "$d/commands.tmp" && mv "$d/commands.tmp" "$d/commands"
	' &>/dev/null &) &>/dev/null
}

# fztype -- fuzzy command lookup.
# Usage: fztype [-p|--prefix] [-r|--refresh] <command>
#
# Modes:
#   (default)  Cached non-prefix fuzzy: reads from ~/.cache/fztype/commands,
#              spawns background refresh if cache predates today 00:00.
#              Falls back to -r behavior when cache is missing or empty.
#   -p         Prefix real-time fuzzy: compgen -c <first-char>, no cache I/O.
#              Same matching strategy as the original fztype.
#   -r         Non-prefix real-time fuzzy: compgen -c (all commands), fuzzy
#              filter, then atomically update cache in background.
#
# All modes fuzzy-filter via _fzmatch (subsequence, order-preserving).
fztype() {
	local mode="default" term=""

	# Parse flags
	while [[ "${1:-}" == -* ]]; do
		case "$1" in
		-p | --prefix)
			mode="prefix"
			shift
			;;
		-r | --refresh)
			mode="refresh"
			shift
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
		echo "Usage: fztype [-p|--prefix] [-r|--refresh] <command>" >&2
		return 1
	fi

	local CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/fztype"
	local CACHE_FILE="$CACHE_DIR/commands"
	local matches=() raw

	case "$mode" in
	prefix)
		_fzfilter "$term" matches < <(compgen -c "${term:0:1}" | sort -u)
		;;
	refresh)
		raw=$(compgen -c | sort -u)
		_fzcache_write "$raw"
		_fzfilter "$term" matches <<<"$raw"
		;;
	default)
		if [ -s "$CACHE_FILE" ]; then
			# Check midnight expiry.
			local cache_mtime midnight_ts
			cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
			midnight_ts=$(date -d 'today 00:00' +%s 2>/dev/null || echo 0)
			if [ "$cache_mtime" -lt "$midnight_ts" ] 2>/dev/null; then
				_fzcache_refresh
			fi
			_fzfilter "$term" matches <"$CACHE_FILE"
		else
			# No cache -- behave like refresh mode.
			raw=$(compgen -c | sort -u)
			_fzcache_write "$raw"
			_fzfilter "$term" matches <<<"$raw"
		fi
		;;
	esac

	if ((${#matches[@]} == 0)); then
		echo "fztype: no commands matching '${term}'" >&2
		return 1
	fi

	for cmd in "${matches[@]}"; do
		local cmd_type path
		cmd_type=$(type -t "$cmd" 2>/dev/null)
		# fallback: non-interactive shells may not report aliases via type -t
		if [ -z "$cmd_type" ] && alias "$cmd" &>/dev/null; then
			cmd_type="alias"
		fi
		case "$cmd_type" in
		alias) printf '%-30s %s\n' "$cmd" "[alias]" ;;
		function) printf '%-30s %s\n' "$cmd" "[function]" ;;
		builtin) printf '%-30s %s\n' "$cmd" "[builtin]" ;;
		keyword) printf '%-30s %s\n' "$cmd" "[keyword]" ;;
		file)
			path=$(type -p "$cmd" 2>/dev/null)
			printf '%-30s %s\n' "$cmd" "${path:-[not found]}"
			;;
		*) printf '%-30s %s\n' "$cmd" "[${cmd_type:-unknown}]" ;;
		esac
	done
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
