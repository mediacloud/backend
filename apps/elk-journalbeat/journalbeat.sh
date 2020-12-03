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

if ! grep -qs '/var/log/journal ' /proc/mounts; then
    echo "/var/log/journal/ is not mounted."
    exit 1
fi

EXPECTED_JOURNALD_MACHINE_DIR="/var/log/journal/$(cat /etc/machine-id)"
if [ ! -d "${EXPECTED_JOURNALD_MACHINE_DIR}" ]; then
    echo "journald's expected machine directory ${EXPECTED_JOURNALD_MACHINE_DIR} was not found;"
    echo "/etc/machine-id mismatch?"
    exit 1
fi

# Make sure current version of journalctl is able to read the mounted data
if ! journalctl --header | grep -q 'Machine ID:'; then
    echo "journalctl doesn't seem to be able to read logs; systemd version mismatch?"
    exit 1
fi

exec /opt/journalbeat/journalbeat \
    -E name=$(cat /etc/hostname) \
    -E max_procs=$(/container_cpu_limit.sh) \
    --strict.perms=false \
    --environment=container \
    run
