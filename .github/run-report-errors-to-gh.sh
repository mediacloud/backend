#!/bin/bash
#
# Run an argument command, report log in a GitHub Actions annotation if it fails
#
# https://help.github.com/en/actions/reference/workflow-commands-for-github-actions#setting-an-error-message
#
# Both STDOUT and STDERR of subcommand get written to STDOUT
#

set -u
# No "set -e" as argument command might fail

if [ "$#" -lt 1 ]; then
    >&2 echo "Usage: $0 command"
    exit 1
fi

# Pipe FD 5 to STDOUT
exec 5>&1

# 1) Run command
# 2) Log both STDOUT and STDERR to CMD_OUTPUT
# 3) Copy command's output to FD 5
# 5) Exit with original command's exit status to be able to use it later
CMD_OUTPUT=$($@ 2>&1 | tee >(cat - >&5); exit ${PIPESTATUS[0]})
CMD_STATUS=$?

if [ $CMD_STATUS -ne 0 ]; then

    # Get rid of own script name
    CMD_OUTPUT="${CMD_OUTPUT/$0/}"

    # Escape some special characters
    CMD_OUTPUT="${CMD_OUTPUT//$'\r'/%0D}"
    CMD_OUTPUT="${CMD_OUTPUT//$'\n'/%0A}"
    CMD_OUTPUT="${CMD_OUTPUT//$'::'/%3A%3A}"

    # Try to identify filename of a test that was run; assume that the test
    # filename is more likely to be at the end of array
    TEST_FILENAME=""
    for (( arg_idx=$#; arg_idx>0; arg_idx-- )); do
        arg="${!arg_idx}"

        # Argument might be a whole command, e.g. "./dev/run_test.py ..."
        IFS=', ' read -r -a subargs <<< "$arg"

        for (( subarg_idx=${#subargs[@]}-1 ; subarg_idx>=0 ; subarg_idx-- )) ; do

            subarg="${subargs[subarg_idx]}"

            if [ -f "${subarg}" ]; then
                TEST_FILENAME="${subarg}"
                break
            fi

        done

        if [ ! -z "$TEST_FILENAME" ]; then
            break
        fi

    done

    if [ -z "$TEST_FILENAME" ]; then
        TEST_FILENAME="UNKNOWN_TEST"
    fi

    PWD=$(pwd)
    TEST_FILENAME=$(echo ${TEST_FILENAME} | sed "s|${PWD}/||g")

    # Print GitHub Actions annotation
    echo "::error file=${TEST_FILENAME}::${CMD_OUTPUT}"
fi

exit $CMD_STATUS
