#!/usr/bin/env zsh

pushd -q ${HOME}/devel/vera

print "\n>> copying extra mods..."

git checkout master &> /dev/null

fetch_out="$(git fetch 2>&1)"

# grab the latest version, if needed
if [[ -n $fetch_out ]]; then
  print ">> pulling latest vera code...\n"
  pull_out="$(git pull 2>&1)"
fi

pushd -q lib
extra_mods=(*/*.ex)

for f in ${extra_mods}; do
  cp --verbose $f /usr/local/helen/extra-mods/always
done

print "\n"
