#!/bin/bash
#
# Print memory size available to the container, in megabytes
#

set -u
set -e

# Pre-5.8.0 kernels
MC_CGROUP_MEMORY_LIMIT_FILE="/sys/fs/cgroup/memory/memory.limit_in_bytes"
if [ ! -e "${MC_CGROUP_MEMORY_LIMIT_FILE}" ]; then

    # Post-5.8.0 kernels
    MC_CGROUP_MEMORY_LIMIT_FILE="/sys/fs/cgroup/memory.max"
    if [ ! -e "${MC_CGROUP_MEMORY_LIMIT_FILE}" ]; then
        echo "Control group's memory limit file is not available."
        exit 1
    fi

fi

# Read cgroup's memory limit and the total size of available memory, pick the smallest
MC_CGROUP_MEMORY_LIMIT=$(cat "${MC_CGROUP_MEMORY_LIMIT_FILE}")
MC_RAM_SIZE=$(free -b | grep Mem | awk '{ print $2 }')

if [ "$MC_CGROUP_MEMORY_LIMIT" = "max" ] || [ "$MC_CGROUP_MEMORY_LIMIT" -gt "$MC_RAM_SIZE" ]; then
    MC_MEMORY_LIMIT="$MC_RAM_SIZE"
else
    MC_MEMORY_LIMIT="$MC_CGROUP_MEMORY_LIMIT"
fi

echo $(($MC_MEMORY_LIMIT / 1024 / 1024))
