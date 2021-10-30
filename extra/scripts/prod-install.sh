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

setopt local_options rm_star_silent

helen_base=/usr/local/helen_v2
helen_bin=${helen_base}/bin

# pushd -q ${HOME}/devel/shell/local/helen-home/helen_app_ui
# source ./secret-base.sh

pushd -q ${HOME}/devel/helen

tarball=$(ls -t ${HOME}/devel/helen/_build/prod/*.tar.gz | grep --max-count=1 helen)

if [[ ! -f $tarball ]]; then
  echo "${tarball} does not exist, has prod-build.sh been executed?"
  exit 1
fi

pushd -q ${helen_base}

if [[ -f ./bin/helen ]]; then
  print -n "stopping helen... "
  ./bin/helen stop 1> /dev/null 2>&1
  sleep 5
  # check helen is really shutdown
  ./bin/helen ping 1> /dev/null 2>&1
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

pushd -q ${helen_base}
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

print " done."
