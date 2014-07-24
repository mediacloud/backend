#!/bin/bash

./script/run_with_carton.sh ./script/mediawords_psql_wrapper.pl  --dump-env-commands --db-label test > /tmp/test_db_$$
echo /tmp/test_db_$$
pg_restore --clean -d $PGDATABASE data/db_dumps/cc_blogs_mc_db.dump
MEDIAWORDS_FORCE_USING_TEST_DATABASE=1 ./script/run_with_carton.sh ./script/mediawords_import_solr_data.pl --delete 
