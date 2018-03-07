#!/bin/bash

set -u
set -e

#
# Generate and submit test coverage report to Coveralls.io
# ---
#

echo "Installing Coveralls Perl utilities to be able to report test coverage..."
sudo lxc exec $MC_LXD_CONTAINER -- sudo -H -u $MC_LXD_USER /bin/bash -c "\
    cd $MC_LXD_MEDIACLOUD_ROOT; \
    ./script/run_in_env.sh cpanm --notest Devel::Cover Devel::Cover::Report::Coveralls
    "

echo "Installing Coveralls Python utilities to be able to report test coverage..."
sudo lxc exec $MC_LXD_CONTAINER -- sudo -H -u $MC_LXD_USER /bin/bash -c "\
    cd $MC_LXD_MEDIACLOUD_ROOT; \
    ./script/run_in_env.sh pip install --upgrade coveralls
    "

echo "Generating Coveralls-compatible JSON report for Python code (./coverage.json)..."
sudo lxc exec $MC_LXD_CONTAINER -- sudo -H -u $MC_LXD_USER /bin/bash -c "\
    cd $MC_LXD_MEDIACLOUD_ROOT; \
    export TRAVIS=$TRAVIS; \
    export TRAVIS_JOB_ID=$TRAVIS_JOB_ID; \
    export TRAVIS_BRANCH=$TRAVIS_BRANCH; \
    ./script/run_in_env.sh coveralls --output=coverage.json
    "

echo "Generating Coveralls-compatible JSON report for Perl code (./cover_db/coveralls.json)..."
sudo lxc exec $MC_LXD_CONTAINER -- sudo -H -u $MC_LXD_USER /bin/bash -c "\
    cd $MC_LXD_MEDIACLOUD_ROOT; \
    export TRAVIS=$TRAVIS; \
    export TRAVIS_JOB_ID=$TRAVIS_JOB_ID; \
    export TRAVIS_BRANCH=$TRAVIS_BRANCH; \
    ./script/run_in_env.sh cover -report CoverallsJSON
    "

echo "Merging Perl report (./cover_db/coveralls.json) into Python report (./coverage.json), submitting everything to Coveralls.io..."
sudo lxc exec $MC_LXD_CONTAINER -- sudo -H -u $MC_LXD_USER /bin/bash -c "\
    cd $MC_LXD_MEDIACLOUD_ROOT; \
    export TRAVIS=$TRAVIS; \
    export TRAVIS_JOB_ID=$TRAVIS_JOB_ID; \
    export TRAVIS_BRANCH=$TRAVIS_BRANCH; \
    ./script/run_in_env.sh coveralls --merge=cover_db/coveralls.json
    "

# Travis's own scripts might have undefined variables or errors
set +u
set +e
