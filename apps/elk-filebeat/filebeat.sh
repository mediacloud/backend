#!/bin/bash

set -u
set -e

if ! grep -qs '/etc/hostname ' /proc/mounts; then
    echo "/etc/hostname is not mounted."
    exit 1
fi

if ! grep -qs '/etc/machine-id ' /proc/mounts; then
    echo "/etc/machine-id is not mounted."
    exit 1
fi

if ! grep -qs '/var/log ' /proc/mounts; then
    echo "/var/log/ is not mounted."
    exit 1
fi

if ! grep -qs '/var/lib/docker ' /proc/mounts; then
    echo "/var/lib/docker/ is not mounted."
    exit 1
fi

# Test for existence of socket as docker.sock might show up under /run in the mount table
if [ ! -S "/var/run/docker.sock" ]; then
    echo "/var/run/docker.sock is not mounted."
    exit 1
fi

exec /opt/filebeat/filebeat \
    -E name=$(cat /etc/hostname) \
    -E max_procs=$(/container_cpu_limit.sh) \
    --strict.perms=false \
    --environment=container
