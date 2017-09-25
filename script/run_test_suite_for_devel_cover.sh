#!/bin/bash
#
# Run the test suite with Devel::Cover
#
# Usage:
#
#     # create test coverage database:
#     ./script/run_test_suite_for_devel_cover.sh
#

set -e
set -u
set -o errexit

cd `dirname $0`/../

DESTROY_SOLR="0"

if [[ $# == 1 && -n "$1" ]]; then
    if [ '--destroy-solr' = "$1" ]; then
        echo "set destroy solr"
        DESTROY_SOLR=1
    fi
fi

echo "Removing old test coverage database..." 1>&2
rm -rf cover_db/

echo "Running full test suite..." 1>&2
HARNESS_PERL_SWITCHES='-MDevel::Cover=+ignore,t/,+ignore,\.t$' \
    ./script/run_test_suite.sh
