#!/usr/bin/env zsh

if [[ $USER != 'helen' ]]; then
  sudo su --command \
  '${HOME}/devel/helen/extra/scripts/prod-release.sh' helen
  exit $?
fi

pushd -q ${HOME}/devel/helen

fetch_out=$(git fetch 2>&1)

# grab the latest version, if needed
if [[ -n $fetch_out ]]; then
  pull_out="$(git pull 2>&1)"
fi

pushd -q ${HOME}/devel/helen/extra/scripts

./prod-build.sh && ./prod-install.sh && ./prod-cp-extra-mods.sh
