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
    RELOAD_TEST_DB=1

    if [ $RELOAD_TEST_DB = 1 ]; then
       echo "Dropping database $PGDATABASE"
       dropdb $PGDATABASE
       echo "Creating database $PGDATABASE"
       createdb $PGDATABASE
       echo "running pg_restore"
       pg_restore  -d $PGDATABASE data/db_dumps/cc_blogs_mc_db.dump
    fi
fi

UPGRADE_DB_SQL=`script/run_with_carton.sh script/mediawords_upgrade_db.pl --db_label test`

if [ ${#UPGRADE_DB_SQL} -gt 0 ]; then
    script/run_with_carton.sh script/mediawords_upgrade_db.pl --db_label test --import
    pg_dump -F custom mediacloud_test > data/db_dumps/cc_blogs_mc_db.dump
    echo "updated data/db_dumps/cc_blogs_mc_db.dump to new schema"
fi

echo "testing for runnning solr"

if ps aux | grep java | grep -- '-Dsolr' | grep start.jar > /dev/null; then
    echo "Solr is already running (it shouldn't)."
    exit 1
fi

echo "Starting Solr..."
./script/run_with_carton.sh ./solr/scripts/run_singleton_solr_server.pl > /dev/null&
solr_pid=$!

SOLR_IS_UP=0
SOLR_START_RETRIES=90

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

TEST_RETURN_STATUS=0

if [ ! -v MEDIACLOUD_ENABLE_PYTHON_API_TESTS ]; then
    MEDIACLOUD_ENABLE_PYTHON_API_TESTS=0
fi  

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

    if [ $MEDIACLOUD_ENABLE_PYTHON_API_TESTS = 1 ]; then
        echo "starting mediacloud server"

        MEDIACLOUD_ENABLE_SHUTDOWN_URL=1 MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION=1 MEDIAWORDS_FORCE_USING_TEST_DATABASE=1 ./script/run_server_with_carton.sh &
        mc_server_pid=$!

        echo "Media Cloud server PID $mc_server_pid"
        MC_IS_UP=0
        MC_START_RETRIES=90
        echo "Waiting $MC_START_RETRIES seconds for Media Cloud server to start..."
        for i in `seq 1 $MC_START_RETRIES`; do
            echo "Trying to connect (#$i)..."
            if nc -z -w 10 127.0.0.1 3000; then
                echo "Mediacloud is up"
                MC_IS_UP=1
                break
            else
                # Still down
                sleep 1
            fi
            done

        cd MediaCloud-API-Client
        if python test.py; then
           echo "Python API test succeeded"
        else
            TEST_RETURN_STATUS=$?
            echo "Python API test failed with status: $TEST_RETURN_STATUS"
        fi  
      
        cd ..
        pwd
        curl 'http://0:3000/admin/stop_server' &   
        sleep 1
        echo "past curl"
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
