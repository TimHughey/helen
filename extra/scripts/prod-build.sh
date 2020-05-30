#!/usr/bin/env zsh
pushd -q ${HOME}/devel/helen

git pull && env MIX_ENV=prod mix release helen --overwrite

popd -q
