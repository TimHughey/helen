#!/usr/bin/env zsh
pushd -q ${HOME}/devel/helen

if [[ -v SKIP_PULL ]]; then
  print -P "\n$fg_bold[yellow]* skipping git pull, as requested%f\n"
  env MIX_ENV=prod mix release helen --overwrite
else
  git pull && env MIX_ENV=prod mix release helen --overwrite
fi

popd -q 
