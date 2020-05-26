#!/usr/bin/env zsh

if [[ $USER != 'helen' ]]; then
  sudo su --command 'pushd ${HOME}/devel/helen/extra/bin/do-prod-release.sh' helen
  exit 0
fi

pushd -q ${HOME}/devel/helen

if [[ -v SKIP_PULL ]]; then
  print -P "\n$fg_bold[yellow]* skipping git pull, as requested%f\n"
  env MIX_ENV=prod mix release helen --overwrite
else
  git pull && env MIX_ENV=prod mix release helen --overwrite
fi

pushd -q extra/bin

./prod-install.sh && ./tail-log.sh

popd -q +2
