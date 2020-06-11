#!/usr/bin/env zsh
pushd -q ${HOME}/devel/helen

env MIX_ENV=prod mix release helen --overwrite
