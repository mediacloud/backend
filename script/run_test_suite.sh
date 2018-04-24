#!/bin/bash
#
# Run Media Cloud test suite (Perl and Python tests)
#
# If MC_TEST_SUITE_REPORT_COVERAGE environment variable is set, generate and
# report test coverage.
#

# ---

set -u
set -e
set -o  errexit

# Some dedicated server companies set the hostnames of their
# virtual servers to numeric values (such as 288066). The test suite is
# then unable to access http://288066/

function hostname_help {
    echo "Please set the hostname to an alphanumeric value, e.g.:"
    echo "    export HOSTNAME=mediacloud"
    echo "    sudo hostname mediacloud"
    echo "    echo 127.0.0.1 \`hostname\` | sudo tee -a /etc/hosts"
    echo "and then try again."
}

system_hostname=`hostname`
shell_hostname="$HOSTNAME"      # internal bash variable
if [[ -z "$system_hostname" || "$system_hostname" == "(none)"
    || -z "$shell_hostname" || "$shell_hostname" == "(none)" ]]; then

    echo "Unable to determine hostname or hostname is empty."
    hostname_help
    exit 1
fi
if [[ "$system_hostname" =~ ^[0-9]+$ || "$shell_hostname" =~ ^[0-9]+$ ]] ; then
    echo "Your hostname ('$HOSTNAME') consists only of integers and thus some of the tests might fail."
    hostname_help
    exit 1
fi

if [ ! -z ${MC_TEST_SUITE_REPORT_COVERAGE+x} ]; then

    echo "Removing old test coverage reports..."
    rm -rf cover_db/ .coverage coverage.json

    # Enable Perl's Devel::Cover
    export HARNESS_PERL_SWITCHES='-MDevel::Cover=+ignore,t/,+ignore,\.t$'

    # Enable Python's pytest coverage
    PYTEST_ARGS="--cov=mediacloud/mediawords/ --cov-config=mediacloud/setup.cfg"

else

    PYTEST_ARGS=""

fi

# Run test suite
cd `dirname $0`/../

echo "Running Python linter"
./script/run_in_env.sh flake8 mediacloud/mediawords

echo "Running Python unit tests..."
./script/run_in_env.sh pytest $PYTEST_ARGS --verbose mediacloud/ || {
    echo "One or more Python tests have failed with error code $?."
    exit 1
}

ALL_TEST_FILES=`find lib script t -name '*.t' | sort`

if [ -z ${MC_TEST_CHUNK+x} ]; then
    echo "Running all Perl unit tests..."
    TEST_FILES="$ALL_TEST_FILES"

else

    if [ "$MC_TEST_CHUNK" -gt 4 ]; then
        echo "Only up to 4 chunks are supported."
        exit 1
    fi

    echo "Running chunk $MC_TEST_CHUNK of Perl unit tests..."

    function join_by { local IFS="$1"; shift; echo "$*"; }
    
    current_chunk=1
    TEST_FILES=()
    while read test_file; do
        if [ "$current_chunk" -eq "$MC_TEST_CHUNK" ]; then
            TEST_FILES+=($test_file)
        fi

        current_chunk=$((current_chunk+1))
        if [ "$current_chunk" -gt 4 ]; then
            current_chunk=1
        fi

    done < <(echo "$ALL_TEST_FILES")

    TEST_FILES=$(join_by $'\n' "${TEST_FILES[@]}")

fi

TEST_FILES="${TEST_FILES//$'\n'/ }"

echo "Running Perl unit tests: $TEST_FILES..."

PERL5OPT=-MCarp::Always ./script/run_in_env.sh prove $* $TEST_FILES || {
    echo "One or more Perl tests have failed with error code $?."
    exit 1
}
