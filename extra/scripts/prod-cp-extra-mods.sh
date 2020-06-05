#!/usr/bin/env zsh

pushd -q ${HOME}/devel/vera

git checkout master &> /dev/null

fetch="$(git fetch)"

# grab the latest version, if needed
if [[ -n $fetch ]]; then
  print "\npulling latest vera code...\n"
  git pull &> /dev/null
fi

pushd -q lib
extra_mods=(*/*.ex)

for f in ${extra_mods}; do
  cp --verbose $f /usr/local/helen/extra-mods
done
