#!/bin/bash

echo "setting up test database"
./script/run_with_carton.sh ./script/mediawords_psql_wrapper.pl  --dump-env-commands --db-label test > /tmp/test_db_$$
source  /tmp/test_db_$$
echo "running pg_restore"
pg_restore --clean -d $PGDATABASE data/db_dumps/cc_blogs_mc_db.dump

echo "testing for runnning solr"

ps aux | grep java | grep -- '-Dsolr' | grep start.jar > /dev/null

if [ $? -ne 0 ]; then
echo "need to start solr"
./script/run_with_carton.sh ./solr/scripts/run_singleton_solr_server.pl > /dev/null&
solr_pid=$!
echo "pausing to let solr start"
sleep 10
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

