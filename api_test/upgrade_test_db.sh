#!/bin/bash

set -u
set -o  errexit

cd `dirname $0`/../

echo "setting up test database"
./script/run_with_carton.sh ./script/mediawords_psql_wrapper.pl  --dump-env-commands --db-label test > /tmp/test_db_$$
source  /tmp/test_db_$$

if [[ "$PGDATABASE" != "mediacloud_test" ]]; then
    echo "aborting test database name ($PGDATABASE) must be mediacloud_test"
    exit -1
else
    echo "Dropping database $PGDATABASE"
    dropdb $PGDATABASE
    echo "Creating database $PGDATABASE"
    createdb $PGDATABASE
    echo "Loading test dump"
    psql -d $PGDATABASE -f data/db_dumps/cc_blogs_mc_db.sql
fi

echo "running mediawords_upgrade_db.pl --import"
MEDIAWORDS_FORCE_USING_TEST_DATABASE=1 ./script/run_with_carton.sh ./script/mediawords_upgrade_db.pl --import
echo "dumping"
pg_dump --no-owner --format=plain $PGDATABASE > data/db_dumps/cc_blogs_mc_db.sql
