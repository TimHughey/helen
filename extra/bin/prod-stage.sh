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

if [[ ! -f $helen_tarball ]]; then
  print "deploy tar $helen_tarball doesn't exist, doing nothing."
  return 1
fi

print -n "untarring $helen_tarball into $helen_base_new"

run_cmd sudo /bin/rm -rf $helen_base_new
run_cmd sudo /bin/mkdir --mode 0775 $helen_base_new
run_cmd sudo /bin/chown helen:helen $helen_base_new
tar -C $helen_base_new -xf $helen_tarball && print " done."

print -n "removing deploy tarball..." && rm -f $helen_tarball && print " done."

print -n "correcting permissions... "
chmod -R g+X $helen_base_new && print "done."
