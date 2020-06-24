#!/usr/bin/env zsh

helen_base=/usr/local/helen
helen_bin=${helen_base}/bin
helen=${helen_bin}/helen

print -n "waiting for helen to start... "

pushd -q /usr/local/helen/bin

until ./helen pid 1>/dev/null 2>/dev/null; do
  sleep 1
done

popd -q

print "done, pid=${helen_pid}"

pushd -q /usr/local/helen/tmp/log

log_file=(erlang.*(om[1]))

print "tailing ${log_file} log file. (use CTRL+C to stop)"
tail --lines=15 -f erlang.*(om[1]) 

exit 0
