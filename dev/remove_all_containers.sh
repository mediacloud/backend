#!/bin/bash
#
# Remove all (running and stopped) containers
#
# Used by PyCharm to force recreating all containers before the test run.
#

set -u
set -e

docker container ls -a | grep mc2021/ | awk '{ print $1 }' | xargs docker container rm -f
