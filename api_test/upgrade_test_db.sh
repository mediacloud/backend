#!/bin/bash

set -u
set -o  errexit

cd `dirname $0`/../

echo "setting up test database"
./script/run_with_carton.sh ./script/mediawords_psql_wrapper.pl  --dump-env-commands --db-label test > /tmp/test_db_$$
source  /tmp/test_db_$$
echo "running pg_restore"
pg_restore --clean -d $PGDATABASE data/db_dumps/cc_blogs_mc_db.dump
MEDIAWORDS_FORCE_USING_TEST_DATABASE=1 ./script/run_with_carton.sh ./script/mediawords_upgrade_db.pl --import
echo "dumping"
pg_dump --format=custom $PGDATABASE >  data/db_dumps/cc_blogs_mc_db.dump
