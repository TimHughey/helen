#!/usr/bin/env zsh

pushd -q ${HOME}/devel/helen/extra/scripts
./delete-last-migration.sh $argv[@]
popd -q
