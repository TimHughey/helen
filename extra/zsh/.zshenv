# Use hard limits, except for a smaller stack and no core dumps
unlimit
limit stack 8192
limit core 0
limit -s

umask 022

# automatically remove duplicates from these arrays
typeset -U hosts path cdpath fpath manpath

binpaths=($HOME/bin ${HOME}/.local/bin /usr/local/sbin /usr/sbin /sbin)
for p in $binpaths; do
	if [[ -d $p ]]; then path+=${p}; fi
done

helen_base=/usr/local/helen
if [[ -d $helen_base ]]; then
	path+=$jan_base/bin
	export REPLACE_OS_VARS=true
	export RUN_ERL_LOG_ALIVE_MINUTES=240
	export RUN_ERL_LOG_MAXSIZE=4206592
fi

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
