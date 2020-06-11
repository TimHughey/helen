#!/usr/bin/env zsh

pushd -q ${HOME}/devel/vera

git checkout master &> /dev/null

fetch_out="$(git fetch 2>&1)"

# grab the latest version, if needed
if [[ -n $fetch_out ]]; then
  pull_out="$(git pull 2>&1)"
fi

pushd -q lib
extra_mods=(*/*.ex)

rsync -a --delete-before $extra_mods /usr/local/helen/extra-mods/always
