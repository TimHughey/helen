#!/usr/bin/env zsh

if [[ $USER != 'helen' ]]; then
  sudo su --command \
  '${HOME}/devel/helen/extra/scripts/prod-release.sh' helen
  exit $?
fi

pushd -q ${HOME}/devel/helen/extra/scripts

./prod-build.sh && ./prod-install.sh && ./prod-cp-extra-mods.sh

popd -q
