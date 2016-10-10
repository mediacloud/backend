#!/bin/bash

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

# Returns true (0) if the test suite is being run under Devel::Cover
function running_under_devel_cover {

    # HARNESS_PERL_SWITCHES=-MDevel::Cover make test
    if [ "${HARNESS_PERL_SWITCHES+defined}" = defined ]; then
        if [[ "${HARNESS_PERL_SWITCHES}" == *-MDevel::Cover* ]]; then
            return 0    # true
        fi
    fi

    # PERL5OPT=-MDevel::Cover make test
    if [ "${PERL5OPT+defined}" = defined ]; then
        if [[ "${PERL5OPT}" == *-MDevel::Cover* ]]; then
            return 0    # true
        fi
    fi

    return 1    # false
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

echo "Running Python unit tests..."
set +u
source mc-venv/bin/activate
set -u
nosetests --where=mediacloud/

echo "Running Perl unit tests..."
TEST_FILES=`find lib script t -name '*.t'`
./script/run_carton.sh exec prove -Ilib/ $* $TEST_FILES || {
    echo "One or more unit tests have failed with error code $?."
    exit 1
}
