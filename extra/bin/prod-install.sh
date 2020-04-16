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

if [[ $1 == "--clean" ]]; then
  clean=1
fi

git rev-parse --show-toplevel 1> /dev/null 2> /dev/null
if [[ $? -ne 0 ]]; then
  echo "Must run from project directory"
  exit 1
fi

if [[ $USER != 'helen' ]]; then
  echo "Must run as helen user account"
  exit 1
fi

src_base=$(git rev-parse --show-toplevel)

source $src_base/extra/common/vars.sh

setopt local_options rm_star_silent

if [[ ! -d ${helen_base_new} ]]; then
  echo "${helen_base_new} does not exist, has prod-stage.sh been executed?"
  exit 1
fi

if [[ -f $helen_bin/helen ]]; then
  print -n "stopping helen... "
  $helen_bin/helen stop 1> /dev/null 2>&1
  # check helen is really shutdown
  $helen_bin/helen ping 1> /dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    print "FAILED, aborting install."
    return 1
  else
    print "done."
  fi
fi

print "executing mix ecto.migrate:"
cd $helen_src_base
run_cmd env MIX_ENV=prod mix ecto.migrate
cd $save_cwd

print -n "swapping in new release..."

if [[ -d $helen_base ]]; then
  run_cmd sudo /bin/rm -rf $helen_base_old 1> /dev/null 2>&1
  run_cmd sudo /bin/mv $helen_base $helen_base_old 1> /dev/null 2>&1
fi

run_cmd sudo /bin/mv $helen_base_new $helen_base 1> /dev/null 2>&1 && print " done."

print -n "starting helen..."

$helen_bin/helen daemon

print " done."

if [[ $clean -eq 1 ]]; then
  print -n "removing $helen_base_old..." && run_cmd sudo /bin/rm -rf $helen_base_old && print " done."
else
  print "won't remove ${helen_base_old}, use --clean to do so"
fi
