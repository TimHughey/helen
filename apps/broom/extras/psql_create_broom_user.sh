#!/usr/bin/env zsh

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
SQL=${SCRIPTPATH}/sql

psql -h db.test.wisslanding.com -p 15432 -f ${SQL}/create_broom_user.sql
