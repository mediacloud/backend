#!/bin/bash
#
# Print memory size available to the container, in megabytes
#

set -u
set -e

if [ ! -e /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    echo "Control group's memory limit file is not available."
    exit 1
fi

MC_MEMORY_LIMIT=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)

# If it's some insane value (13 or more digits, nearing a terabyte), either the
# cgroup's memory limit is not set or we're not running in a container at all,
# so return whatever is reported by "free"
if [[ "${#MC_MEMORY_LIMIT}" -ge 13 ]]; then
    MC_MEMORY_LIMIT=$(free -b | grep Mem | awk '{ print $2 }')
fi

echo $(($MC_MEMORY_LIMIT / 1024 / 1024))
