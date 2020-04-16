#!/usr/bin/env zsh

helen_base=/usr/local/helen
helen_bin=${helen_base}/bin
helen=${helen_bin}/helen

print -n "waiting for helen to start... "

until $helen pid 1>/dev/null 2>/dev/null; do
  sleep 1
done

print "done."

helen_pid=$($helen pid)

print "tailing helen log file. (use CTRL+C to stop)"

exec tail --lines=100 --pid=${helen_pid} -f $helen_base/tmp/log/erlang.*(om[1])
