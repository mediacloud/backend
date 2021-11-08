#!/bin/bash
#
# Print CPUs available to the container, as an integer (i.e. 0.25 of CPU gets rounded to 1)
#
# https://www.kernel.org/doc/Documentation/scheduler/sched-bwc.txt
#

set -u
set -e

# Pre-5.8.0 kernels
if [ -e /sys/fs/cgroup/cpu/cpu.cfs_quota_us ]; then

    if [ ! -e /sys/fs/cgroup/cpu/cpu.cfs_period_us ]; then
        echo "Control group's length of a period file is not available."
        exit 1
    fi

    MC_CGROUP_QUOTA=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)
    MC_CGROUP_PERIOD=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)

else

    # Post-5.8.0 kernels
    if [ ! -e /sys/fs/cgroup/cpu.max ]; then
        echo "Control group's cpu.max is not available."
        exit 1
    fi

    MC_CGROUP_QUOTA=$(cat /sys/fs/cgroup/cpu.max | awk '{ print $1 }')
    MC_CGROUP_PERIOD=$(cat /sys/fs/cgroup/cpu.max | awk '{ print $2 }')

fi

if [ "$MC_CGROUP_QUOTA" = "-1" ] || [ "$MC_CGROUP_QUOTA" = "max" ]; then
    # No limit
    MC_CPU_LIMIT="$(nproc)"
else
    # Extra magic to ceil the quotient: https://stackoverflow.com/a/12536521
    MC_CPU_LIMIT=$((($MC_CGROUP_QUOTA + $MC_CGROUP_PERIOD - 1) / $MC_CGROUP_PERIOD))
fi

echo $MC_CPU_LIMIT
