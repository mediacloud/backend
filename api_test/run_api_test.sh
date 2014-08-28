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
    echo "running pg_restore"
    pg_restore  -d $PGDATABASE data/db_dumps/cc_blogs_mc_db.dump
fi


echo "testing for runnning solr"

if ! ps aux | grep java | grep -- '-Dsolr' | grep start.jar > /dev/null; then
echo "need to start solr"
./script/run_with_carton.sh ./solr/scripts/run_singleton_solr_server.pl > /dev/null&
solr_pid=$!
echo "pausing to let solr start"
sleep 30
else
echo "Solr must not be running"
exit -1
fi
MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION=1 MEDIAWORDS_FORCE_USING_TEST_DATABASE=1 ./script/run_with_carton.sh ./script/mediawords_import_solr_data.pl --delete 
MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION=1 MEDIAWORDS_FORCE_USING_TEST_DATABASE=1 ./script/run_carton.sh exec prove -Ilib/ api_test/api_media.t

if [ $solr_pid ]; then
echo killing solr pid $solr_pid
kill  $solr_pid
fi

