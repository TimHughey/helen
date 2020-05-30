#!/usr/bin/env zsh

pushd -q /usr/local/helen/tmp/log

log_file="erlang.*(om[1])"

less ${log_file}

popd -q

exit 0
