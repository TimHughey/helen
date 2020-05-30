#!/usr/bin/env zsh

pushd -q ${HOME}/devel/helen

export MIX_ENV=test
export HELEN_ENV=test
export HELEN_HOST=$(hostname -f)

mix release helen --overwrite --quiet

pushd -q _build/test/rel/helen

./bin/helen start_iex

# back to starting cwd
popd -q
