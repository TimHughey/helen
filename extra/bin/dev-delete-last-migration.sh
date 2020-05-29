#!/usr/bin/env zsh

pushd -q ${HOME}/devel/helen
psql --host db.dev.wisslanding.com\
     --port 15432 \
     --file=./extra/sql-snippets/delete-migration.sql \
     helen_dev

popd -q
