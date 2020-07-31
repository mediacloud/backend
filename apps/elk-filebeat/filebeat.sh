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

# We need Kibana to be up to be able to preload it with dashboards
# for i in {1..120}; do
#     echo "Waiting for Kibana to start..."
#     if curl --fail --silent http://elk-kibana:5601/api/status; then
#         break
#     else
#         sleep 1
#     fi
# done

exec /opt/filebeat/filebeat \
    -E name=$(cat /etc/hostname) \
    -E max_procs=$(/container_cpu_limit.sh) \
    --strict.perms=false \
    --environment=container
