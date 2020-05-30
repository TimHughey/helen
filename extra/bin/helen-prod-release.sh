#!/usr/bin/env zsh

pushd -q ${HOME}/devel/helen/extra/scripts

./prod-release.sh && ./tail-log.sh

popd -q
