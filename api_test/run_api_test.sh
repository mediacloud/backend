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

    SOLR_IS_UP=0
    SOLR_START_RETRIES=30

    echo "Waiting $SOLR_START_RETRIES seconds for Solr to start..."
    for i in `seq 1 $SOLR_START_RETRIES`; do
        echo "Trying to connect (#$i)..."
        if nc -z -w 10 127.0.0.1 8983; then
            echo "Solr is up"
            SOLR_IS_UP=1
            break
        else
            # Still down
            sleep 1
        fi
    done

    if [ $SOLR_IS_UP = 1 ]; then
        echo "Solr is up."
    else
        echo "Solr is down after $SOLR_START_RETRIES seconds, giving up."
        exit 1
    fi

else
    echo "Solr must not be running"
    exit -1
fi

TEST_RETURN_STATUS=0

if MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION=1 MEDIAWORDS_FORCE_USING_TEST_DATABASE=1 \
   ./script/run_with_carton.sh ./script/mediawords_import_solr_data.pl --delete; then

    echo "Importing Solr data succeeded."

    if MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION=1 MEDIAWORDS_FORCE_USING_TEST_DATABASE=1 \
       ./script/run_carton.sh exec prove -Ilib/ api_test/api_media.t; then

        echo "API test succeeded."

    else
        TEST_RETURN_STATUS=$?
        echo "API test failed with status: $TEST_RETURN_STATUS"
    fi

else
    TEST_RETURN_STATUS=$?
    echo "Importing Solr data failed with status: $TEST_RETURN_STATUS"
fi


if [ $solr_pid ]; then
    echo "killing solr pid $solr_pid"
    kill $solr_pid
fi

exit $TEST_RETURN_STATUS
