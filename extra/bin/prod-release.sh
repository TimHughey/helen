#!/usr/bin/env zsh

git rev-parse --show-toplevel 1> /dev/null 2> /dev/null
if [[ $? -ne 0 ]]; then
  echo "Must run from project directory"
  exit 1
fi

if [[ $USER != 'helen' ]]; then
  echo "Must run as helen user account"
  exit 1
fi

base=$(git rev-parse --show-toplevel)

source $base/extra/common/vars.sh

cd $helen_extra/bin

./prod-build.sh && ./prod-install.sh && ./tail-log.sh

cd $save_cwd
