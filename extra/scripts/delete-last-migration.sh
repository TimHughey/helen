#!/usr/bin/env zsh

pushd -q ${HOME}/devel/helen

case $argv[1] in
test)
  host=db.test.wisslanding.com
  inst=sally_test
  port=15432
  ;;

*)
  host=db.dev.wisslanding.com
  inst=sally_test
  port=15432
  ;;
esac

echo "removing last ecto migration ${inst}"

psql --host ${host} --port ${port} \
      --file=./extra/sql-snippets/delete-migration.sql \
     ${inst}
