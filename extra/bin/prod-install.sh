#!/usr/bin/env zsh

function run_cmd {
    "$@"
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo " "
        echo "error with $1" >&2
        cd $save_cwd
        exit 1
    fi
    return $rc
}

if [[ $USER != 'helen' ]]; then
  sudo su - helen --command ./devel/helen/extra/bin/prod-install.sh
fi

pushd -q ${HOME}/devel/helen

helen_base=/usr/local/helen
helen_bin=${helen_base}/bin

setopt local_options rm_star_silent

tarball="$(pwd)/_build/prod/helen.tar.gz"
if [[ ! -f $tarball ]]; then
  echo "${tarball} does not exist, has prod-build.sh been executed?"
  exit 1
fi

pushd -q /usr/local/helen/bin

if [[ -f ./helen ]]; then
  print -n "stopping helen... "
  ./helen stop 1> /dev/null 2>&1
  # check helen is really shutdown
  ./helen ping 1> /dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    print "FAILED, aborting install."
    return 1
  else
    print "done."
  fi
fi

popd -q

print "executing mix ecto.migrate..."

run_cmd env MIX_ENV=prod mix ecto.migrate

pushd -q /usr/local/helen
print -n "untarring $helen_tarball into `pwd`"
tar -xf $helen_tarball && print " done."
popd -q

print -n "starting helen..."

$helen_bin/helen daemon

popd -q

print " done."
