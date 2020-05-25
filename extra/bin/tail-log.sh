#!/usr/bin/env zsh

helen_base=/usr/local/helen
helen_bin=${helen_base}/bin
helen=${helen_bin}/helen

print -n "waiting for helen to start... "

pushd -q /usr/local/helen/bin

until ./helen pid 1>/dev/null 2>/dev/null; do
  sleep 1
done

helen_pid=$(./helen pid)

popd -q

print "done, pid=${helen_pid}"

pushd -q /usr/local/helen/tmp/log

print "tailing helen log file. (use CTRL+C to stop)"

tail --lines=40 --pid=${helen_pid} -f erlang.*(om[1])

popd -q

exit 0
