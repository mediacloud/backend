#!/bin/bash
#
# Run an argument command, time it out in 10 minutes, return appropriate exit code
#
# Adapted from http://www.bashcookbook.com/bashinfo/source/bash-4.0/examples/scripts/timeout3
#

set -u
# No "set -e" as argument command might fail

if [ "$#" -lt 1 ]; then
    >&2 echo "Usage: $0 command"
    exit 1
fi


# Command timeout
declare -i timeout=600

# Interval between checks if the process is still alive
declare -i interval=1

# Delay between posting the SIGTERM signal and destroying the process by SIGKILL
declare -i delay=60


# kill -0 pid   Exit code indicates if a signal may be sent to $pid process.
(
    ((t = timeout))

    while ((t > 0)); do
        sleep $interval
        kill -0 $$ || exit 0
        ((t -= interval))
    done

    # Be nice, post SIGTERM first.
    # The 'exit 0' below will be executed if any preceeding command fails.
    echo "Command '$@' didn't finish in ${timeout} seconds, sending SIGTERM..."
    kill -s SIGTERM $$ && kill -0 $$ || exit 0
    sleep $delay

    echo "Command '$@' is still running (?) after ${delay}, sending SIGKILL..."
    kill -s SIGKILL $$

) 2> /dev/null &

exec "$@"
