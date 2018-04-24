#!/bin/bash

set -u
set -e

echo "Running test suite on container..."
sudo lxc exec $MC_LXD_CONTAINER -- sudo -H -u $MC_LXD_USER /bin/bash -c "\
cd $MC_LXD_MEDIACLOUD_ROOT; \
    \
    export MC_FACEBOOK_APP_ID=$MC_FACEBOOK_APP_ID; \
    export MC_FACEBOOK_APP_SECRET=$MC_FACEBOOK_APP_SECRET; \
    export MC_AMAZON_S3_TEST_ACCESS_KEY_ID=$MC_AMAZON_S3_TEST_ACCESS_KEY_ID; \
    export MC_AMAZON_S3_TEST_SECRET_ACCESS_KEY=$MC_AMAZON_S3_TEST_SECRET_ACCESS_KEY; \
    export MC_AMAZON_S3_TEST_BUCKET_NAME=$MC_AMAZON_S3_TEST_BUCKET_NAME; \
    export MC_AMAZON_S3_TEST_DIRECTORY_NAME=$MC_AMAZON_S3_TEST_DIRECTORY_NAME; \
    export MC_UNIVISION_TEST_URL=$MC_UNIVISION_TEST_URL; \
    export MC_UNIVISION_TEST_CLIENT_ID=$MC_UNIVISION_TEST_CLIENT_ID; \
    export MC_UNIVISION_TEST_CLIENT_SECRET=$MC_UNIVISION_TEST_CLIENT_SECRET; \
    \
    export MC_SKIP_RABBIT_OPEN_FILES_LIMIT_CHECK=1; \
    export MC_TEST_SUITE_REPORT_COVERAGE=1; \
    \
    export MC_TEST_CHUNK=$MC_TEST_CHUNK; \
    \
    ./script/run_test_suite.sh"

# Travis's own scripts might have undefined variables or errors
set +u
set +e
