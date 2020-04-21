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
#   3.1) Replace ':' from output to '%3A' to avoid GitHub reporting fake annotations
# 5) Exit with original command's exit status to be able to use it later
CMD_OUTPUT=$($@ 2>&1 | tee >(cat - | sed -e 's/:/%3A/g' >&5); exit ${PIPESTATUS[0]})
CMD_STATUS=$?

if [ $CMD_STATUS -ne 0 ]; then

    # Get rid of own script name
    CMD_OUTPUT="${CMD_OUTPUT/$0/}"

    # Escape some special characters
    CMD_OUTPUT="${CMD_OUTPUT//$'\r'/%0D}"
    CMD_OUTPUT="${CMD_OUTPUT//$'\n'/%0A}"
    CMD_OUTPUT="${CMD_OUTPUT//$']'/%5D}"
    CMD_OUTPUT="${CMD_OUTPUT//$':'/%3A}"
    CMD_OUTPUT="${CMD_OUTPUT//$';'/%3B}"

    # Try to identify filename of a test that was run; assume that the test
    # filename is more likely to be at the end of array
    TEST_FILENAME="UNKNOWN_TEST"
    for (( i=$#; i>0; i-- )); do
        arg="${!i}"
        if [ -f "${arg}" ]; then
            TEST_FILENAME="${arg}"
            break
        fi
    done

    # Print GitHub Actions annotation
    echo "::error file=${TEST_FILENAME}::${CMD_OUTPUT}"
fi

exit $CMD_STATUS
