
#
# Example .zshrc file for zsh 4.0
#
# .zshrc is sourced in interactive shells.  It
# should contain commands to set up aliases, functions,
# options, key bindings, etc.
#

# Use hard limits, except for a smaller stack and no core dumps
unlimit
limit stack 8192
limit core 0
limit -s

umask 022

# Shell functions
setenv() { typeset -x "${1}${1:+=}${(@)argv[2,$#]}" }  # csh compatibility
freload() { while (( $# )); do; unfunction $1; autoload -U $1; shift; done }

# Where to look for autoloaded function definitions
fpath=($fpath ~/.zfunc)

# Autoload all shell functions from all directories in $fpath (following
# symlinks) that have the executable bit on (the executable bit is not
# necessary, but gives you an easy way to stop the autoloading of a
# particular shell function). $fpath should not be empty for this to work.
for func in $^fpath/*(N-.x:t); autoload $func

# automatically remove duplicates from these arrays
typeset -U hosts path cdpath fpath manpath

binpaths=(${HOME}/bin ${HOME}/.local/bin /usr/local/sbin /usr/sbin /sbin ${HOME}/devel/xtensa-esp32-elf/bin)
for p in $binpaths; do
	if [[ -d $p ]]; then path+=${p}; fi
done

helen_base=/usr/local/helen
if [[ -d $helen_base ]]; then
	path+=$helen_base/bin
	export REPLACE_OS_VARS=true
	export RUN_ERL_LOG_ALIVE_MINUTES=240
	export RUN_ERL_LOG_MAXSIZE=4206592

	alias helen-start="env PORT=4009 helen start"
	alias helen-stop="helen stop"
	alias helen-remote_console="helen remote_console"
	alias helen-tail-log="tail -f $helen_base/var/log/erlang.log*(om[1])"
	alias helen-less-log="less -f $helen_base/var/log/erlang.log*(om[1])"
fi

[[ /usr/bin/vim ]] && export EDITOR='/usr/bin/vim' && export VISUAL='/usr/bin/vim'

# Set prompts
PROMPT="%B%F{yellow}HELEN%B %B%F{cyan}%m%b%k %B%F{green}%3~ %b%F{yellow}[%h-%?] %B%F{white}%# %b%f%k"
#RPROMPT=' %~'     # prompt for right side of screen

# Some environment variables
export MAIL=/var/spool/mail/$USERNAME
# export LESS=-cex3M
export HELPDIR=/usr/share/zsh/$ZSH_VERSION/help  # directory for run-help function to find docs

MAILCHECK=300
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000
DIRSTACKSIZE=20

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# Set/unset  shell options
setopt		notify globdots correct pushdtohome cdablevars autolist
setopt		cshnullglob	appendhistory histsavenodups
setopt  	correctall autocd recexact longlistjobs
setopt  	autoresume histignoredups pushdsilent noclobber
setopt   	autopushd pushdminus extendedglob rcquotes mailwarning
unsetopt 	bgnice autoparamslash

# Autoload zsh modules when they are referenced
zmodload -a zsh/zpty zpty
zmodload -a zsh/zprof zprof
zmodload -ap zsh/mapfile mapfile
# stat(1) is now commonly an external command, so just load zstat
zmodload -aF zsh/stat b:zstat

# Some nice key bindings
#bindkey '^X^Z' universal-argument ' ' magic-space
#bindkey '^X^A' vi-find-prev-char-skip
#bindkey '^Xa' _expand_alias
#bindkey '^Z' accept-and-hold
#bindkey -s '\M-/' \\\\
#bindkey -s '\M-=' \|

bindkey -v               # vi key bindings

# bindkey -e                 # emacs key bindings
bindkey ' ' magic-space    # also do history expansion on space
bindkey '^I' complete-word # complete on tab, leave expansion to _expand

# Setup new style completion system. To see examples of the old style (compctl
# based) programmable completion, check Misc/compctl-examples in the zsh
# distribution.
autoload -Uz compinit
compinit

# Completion Styles

# list of completers to use
zstyle ':completion:*::::' completer _expand _complete _ignored _approximate

# allow one error for every three characters typed in approximate completer
zstyle -e ':completion:*:approximate:*' max-errors \
    'reply=( $(( ($#PREFIX+$#SUFFIX)/3 )) numeric )'

# insert all expansions for expand completer
zstyle ':completion:*:expand:*' tag-order all-expansions

# formatting and messages
zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format '%B%d%b'
zstyle ':completion:*:messages' format '%d'
zstyle ':completion:*:warnings' format 'No matches for: %d'
zstyle ':completion:*:corrections' format '%B%d (errors: %e)%b'
zstyle ':completion:*' group-name ''

# match uppercase from lowercase
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# offer indexes before parameters in subscripts
zstyle ':completion:*:*:-subscript-:*' tag-order indexes parameters

# command for process lists, the local web server details and host completion
#zstyle ':completion:*:processes' command 'ps -o pid,s,nice,stime,args'
#zstyle ':completion:*:urls' local 'www' '/var/www/htdocs' 'public_html'
zstyle '*' hosts $hosts

# Filename suffixes to ignore during completion (except after rm command)
zstyle ':completion:*:*:(^rm):*:*files' ignored-patterns '*?.o' '*?.c~' \
    '*?.old' '*?.pro' 'LICENSE'
# the same for old style completion
#fignore=(.o .c~ .old .pro)

# ignore completion functions (until the _ignored completer)
zstyle ':completion:*:functions' ignored-patterns '_*'

# ignore the users category (home directories)
zstyle ':completion:*' users

[[ -x /usr/bin/dircolors ]] && eval $(dircolors)

if [[ -o login ]]; then
	[[ -x /usr/bin/uptime ]] && uptime && echo
	[[ -x /usr/bin/fortune ]] && fortune && echo
	[[ -x /usr/local/bin/fortune ]] && fortune && echo
fi
