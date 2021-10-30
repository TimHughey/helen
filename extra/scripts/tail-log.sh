#!/usr/bin/env zsh

helen_base=/usr/local/helen_v2

print -n "waiting for helen to start... "

pushd -q ${helen_base}

until ./bin/helen pid 1>/dev/null 2>/dev/null; do
  sleep 1
done

popd -q

print "done, pid=${helen_pid}"

pushd -q ${helen_base}/tmp/log

log_file=(erlang.*(om[1]))

print "tailing ${log_file} log file. (use CTRL+C to stop)"
tail --lines=15 -f erlang.*(om[1])

exit 0
