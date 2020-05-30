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
    sudo su --command '${HOME}/devel/helen/extra/bin/prod-install.sh' helen
    exit 0
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

# back to devel/helen
popd -q

print "executing mix ecto.migrate..."

run_cmd env MIX_ENV=prod mix ecto.migrate

pushd -q /usr/local/helen
print -n "untarring $tarball into `pwd`"
tar_out=$(tar -xf $tarball)

if [[ ! $? ]]; then
  print " "
  print "tar failed:"
  print "  >> ${tar_out}"
  print " "
  print "starting existing version of helen..."
  ./bin/helen daemon
  popd +q 2
  exit 1
fi

print " done"

print -n "correcting permissions... "
chmod -R g+X . && print "done."

print -n "starting latest release of helen..."

./bin/helen daemon

# back to where we started
popd -q +2

print " done."
