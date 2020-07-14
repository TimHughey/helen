#!/usr/bin/env zsh

pushd -q ${HOME}/devel/shell/local/helen-home/helen_app_ui

source ./secret-base.sh

pushd -q ${HOME}/devel/helen/apps/ui

env MIX_ENV=prod npm run deploy --prefix ./assets
env MIX_ENV=prod mix phx.digest

pushd -q ${HOME}/devel/helen

env MIX_ENV=prod mix release helen --overwrite
