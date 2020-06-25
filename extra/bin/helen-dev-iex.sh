#!/usr/bin/env zsh

pushd -q ${HOME}/devel/helen

export MIX_ENV=dev
export HELEN_ENV=dev
export HELEN_HOST=$(hostname -f)

mix compile || exit 1

mix release helen --overwrite --quiet

pushd -q _build/dev/rel/helen

./bin/helen start_iex

# back to starting cwd
popd -q
