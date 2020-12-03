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

if ! grep -qs '/sys ' /proc/mounts; then
    echo "/sys is not mounted."
    exit 1
fi

if ! grep -qs '/opt/auditbeat/host/bin ' /proc/mounts; then
    echo "/opt/auditbeat/host/bin is not mounted."
    exit 1
fi

if ! grep -qs '/opt/auditbeat/host/usr/bin ' /proc/mounts; then
    echo "/opt/auditbeat/host/usr/bin is not mounted."
    exit 1
fi

if ! grep -qs '/opt/auditbeat/host/sbin ' /proc/mounts; then
    echo "/opt/auditbeat/host/sbin is not mounted."
    exit 1
fi

if ! grep -qs '/opt/auditbeat/host/usr/sbin ' /proc/mounts; then
    echo "/opt/auditbeat/host/usr/sbin is not mounted."
    exit 1
fi

if ! grep -qs '/opt/auditbeat/host/etc ' /proc/mounts; then
    echo "/opt/auditbeat/host/etc is not mounted."
    exit 1
fi

if ! grep -qs '/opt/auditbeat/host/var/log ' /proc/mounts; then
    echo "/opt/auditbeat/host/var/log is not mounted."
    exit 1
fi

if grep -q '/docker/' /proc/1/cgroup; then
    echo "init seems to be in Docker's namespace; forgot to add --pid=host?"
    exit 1
fi

if ! getpcaps $$ 2>&1 | grep -qi AUDIT_CONTROL; then
    echo "No AUDIT_CONTROL capability; forgot to add --cap-add=AUDIT_CONTROL?"
    exit 1
fi

# No idea why, but AUDIT_READ is not visible in getpcaps output in a container:
# if ! getpcaps $$ 2>&1 | grep -qi AUDIT_READ; then
#     echo "No AUDIT_READ capability; forgot to add --cap-add=AUDIT_READ?"
#     exit 1
# fi

exec /opt/auditbeat/auditbeat \
    -E name=$(cat /etc/hostname) \
    -E max_procs=$(/container_cpu_limit.sh) \
    --strict.perms=false \
    --environment=container
