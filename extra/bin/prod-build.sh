#!/usr/bin/env zsh

git rev-parse --show-toplevel 1> /dev/null 2> /dev/null
if [[ $? -ne 0 ]]; then
  echo "Must run from project directory"
  exit 1
fi

src_base=$(git rev-parse --show-toplevel)

source $src_base/extra/common/vars.sh

chdir $helen_src_base

if [[ -v SKIP_PULL ]]; then
  print -P "\n$fg_bold[yellow]* skipping git pull, as requested%f\n"
  env MIX_ENV=prod mix release helen --overwrite
else
  git pull && env MIX_ENV=prod mix release helen --overwrite
fi

chdir $save_cwd
