#!/usr/bin/env zsh

base=${HOME}/devel/helen/apps/ui
src=${base}/assets
static=${base}/priv/static

# remove previously copied semantic ui static assets
pushd -q ${static}
rm -rf semantic/dist

# create path for
mkdir -p semantic/dist

# copy current semantic ui dist to priv static for release
rsync -a ${src}/semantic/dist semantic
