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

# Read cgroup's memory limit and the total size of available memory, pick the smallest
MC_CGROUP_MEMORY_LIMIT=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)
MC_RAM_SIZE=$(free -b | grep Mem | awk '{ print $2 }')

if [ "$MC_CGROUP_MEMORY_LIMIT" -gt "$MC_RAM_SIZE" ]; then
    MC_MEMORY_LIMIT="$MC_RAM_SIZE"
else
    MC_MEMORY_LIMIT="$MC_CGROUP_MEMORY_LIMIT"
fi

echo $(($MC_MEMORY_LIMIT / 1024 / 1024))
