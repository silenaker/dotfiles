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
	while (( i < plen && j < tlen )); do
		if [ "${pattern:i:1}" = "${target:j:1}" ]; then
			((i++))
		fi
		((j++))
	done
	(( i == plen ))
}

# fztype -- fuzzy command lookup.
# Usage: fztype <command>
# Characters of the argument must appear in the command name in order
# (not necessarily consecutively).  Uses the first character to seed
# compgen for performance, then applies full fuzzy filtering.
# Shows each match's type, and the filesystem path for file commands.
fztype() {
	local term="${1:-}"
	if [ -z "$term" ]; then
		echo "Usage: fztype <command>" >&2
		return 1
	fi

	local matches=() cmd seed="${term:0:1}"
	while IFS= read -r cmd; do
		_fzmatch "$term" "$cmd" && matches+=("$cmd")
	done < <(compgen -c "$seed" | sort -u)

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
			alias)    printf '%-30s %s\n' "$cmd" "[alias]"    ;;
			function) printf '%-30s %s\n' "$cmd" "[function]" ;;
			builtin)  printf '%-30s %s\n' "$cmd" "[builtin]"  ;;
			keyword)  printf '%-30s %s\n' "$cmd" "[keyword]"  ;;
			file)     path=$(type -p "$cmd" 2>/dev/null)
			          printf '%-30s %s\n' "$cmd" "${path:-[not found]}" ;;
			*)        printf '%-30s %s\n' "$cmd" "[${cmd_type:-unknown}]" ;;
		esac
	done
}

# ------------------------------------------------------------------
# Prompt
# ------------------------------------------------------------------
if [ "$TERM" != "dumb" ] && [ -z "${INSIDE_EMACS:-}" ]; then
	case "$(id -u)" in
		0) PS1='\[\033[01;31m\]\h\[\033[01;34m\] \w\[\033[00m\]\$ ' ;;  # root: red hostname
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
