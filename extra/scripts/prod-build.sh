#!/usr/bin/env zsh
pushd -q ${HOME}/devel/helen

env MIX_ENV=prod npm run deploy --prefix ./assets
env MIX_ENV=prod mix phx.digest
env MIX_ENV=prod mix release helen --overwrite
