#!/bin/bash

set -u
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

# Run test suite
cd `dirname $0`/../

TEST_FILES=`find lib/ script/ t/ -name '*.t'` 

# make sure compile is included first so that it runs first as slowest test.
# include test_crawler.t because we can have one db or server test here and
# test_crawler.t takes the longest of those to complete
PARALLEL_TESTS="t/compile.t t/test_crawler.t `egrep -L 'HashServer|LocalServer|Test\:\:DB' $TEST_FILES | grep -v t/compile.t`"

# tests that use the Test::DB or one of [Hash|Local]Server modules are not parallel safe
SERIAL_TESTS="`egrep -l 'HashServer|LocalServer|Test\:\:DB' $TEST_FILES | grep -v t/test_crawler.t`"

echo "starting tests.  see data/run_test_suite.log for stderr."

./script/run_carton.sh exec prove -j 4 -Ilib/ $* $PARALLEL_TESTS 2> data/run_test_suite.log || {
    echo "One or more parallel unit tests have failed with error code $?."
    exit 1
}

./script/run_carton.sh exec prove -Ilib/ $* $SERIAL_TESTS 2>> data/run_test_suite.log || {
    echo "One or more serial unit tests have failed with error code $?."
    exit 1
}
