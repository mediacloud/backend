#!/bin/bash
#
# Print CPUs available to the container, as an integer (i.e. 0.25 of CPU gets rounded to 1)
#
# https://www.kernel.org/doc/Documentation/scheduler/sched-bwc.txt
#

set -u
set -e

if [ ! -e /sys/fs/cgroup/cpu/cpu.cfs_quota_us ]; then
    echo "Control group's total available run-time within a period file is not available."
    exit 1
fi

if [ ! -e /sys/fs/cgroup/cpu/cpu.cfs_period_us ]; then
    echo "Control group's length of a period file is not available."
    exit 1
fi

# Read cgroup's memory limit and the total size of available memory, pick the smallest
MC_CGROUP_QUOTA=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)
MC_CGROUP_PERIOD=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)
MC_PHYS_CORE_COUNT=$(nproc)

if [ "$MC_CGROUP_QUOTA" -eq "-1" ]; then
    # No limit
    MC_CPU_LIMIT="$MC_PHYS_CORE_COUNT"
else
    # Extra magic to ceil the quotient: https://stackoverflow.com/a/12536521
    MC_CPU_LIMIT=$((($MC_CGROUP_QUOTA + $MC_CGROUP_PERIOD - 1) / $MC_CGROUP_PERIOD))
fi

echo $MC_CPU_LIMIT
