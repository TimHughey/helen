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

base=$(git rev-parse --show-toplevel)

source $base/extra/common/vars.sh

setopt local_options rm_star_silent

if [[ ! -f $helen_tarball ]]; then
  print "deploy tar $helen_tarball doesn't exist, doing nothing."
  return 1
fi

print -n "untarring $helen_tarball into $helen_base_new"

run_cmd sudo rm -rf $helen_base_new
run_cmd sudo mkdir --mode 0775 $helen_base_new
run_cmd sudo chown helen:helen $helen_base_new
sudo -u helen --login tar -C $helen_base_new -xf $helen_tarball && print " done."

print -n "removing deploy tarball..." && rm -f $helen_tarball && print " done."

print -n "correcting permissions... "
sudo -u helen --login chmod -R g+X $helen_base_new && print "done."

# run_cmd sudo -i helen --login $helen_bin/mcp ping 1> /dev/null 2>&1
print -n "stopping helen... "
sudo -u helen --login $helen_bin/mcp stop
# check mcp really shutdown
sudo -u helen --login $helen_bin/mcp ping 1> /dev/null 2>&1
if [[ $? -eq 0 ]]; then
  print "FAILED, aborting install."
  return 1
else
  print "done."
fi

print "executing mix ecto.migrate:"
cd $helen_base
run_cmd env MIX_ENV=prod mix ecto.migrate
cd $save_cwd

print -n "swapping in new release..."
run_cmd sudo rm -rf $helen_base_old 1> /dev/null 2>&1
run_cmd sudo mv $helen_base $helen_base_old 1> /dev/null 2>&1
run_cmd sudo mv $helen_base_new $helen_base 1> /dev/null 2>&1 && print " done."

print -n "starting helen..."

sudo -u helen --login  $helen_bin/mcp daemon

print " done."




if [[ $clean -eq 1 ]]; then
  print -n "removing $helen_base_old..." && run_cmd sudo rm -rf $helen_base_old && print " done."
else
  print "won't remove ${helen_base_old}, use --clean to do so"
fi
