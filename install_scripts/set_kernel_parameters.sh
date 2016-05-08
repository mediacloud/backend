#!/bin/bash

set -u
set -o errexit

echo "Setting required kernel parameters via sysctl..."

if [ `uname` == 'Darwin' ]; then
    # Mac OS X -- nothing to do
    :
else

	SYSCTL_FILE=/etc/sysctl.d/50-mediacloud.conf

    if [ -f "$SYSCTL_FILE" ]; then
        echo "Kernel properties file $SYSCTL_FILE already exists, please either remove it or add parameters manually."
        exit 1
    fi

    # Overwrite
    sudo tee "$SYSCTL_FILE" <<EOF
#
# Media Cloud kernel parameters
#

# MediaCloud::JobManager's Gearman job broker implementation doesn't reuse
# existing TCP connections so under high load gearmand might run out of TCP
# connections.
net.ipv4.tcp_tw_reuse=1
EOF

    # Reread kernel parameters from /etc
    sudo service procps start

fi

echo "Done setting required kernel parameters via sysctl."

# ---

echo "Setting required kernel parameters via limits.conf..."

if [ `uname` == 'Darwin' ]; then
    # Mac OS X -- nothing to do (not likely to be running production environment on OS X)
    :
else

    LIMITS_FILE=/etc/security/limits.d/50-mediacloud.conf

    if [ -f "$LIMITS_FILE" ]; then
        echo "Limits file $LIMITS_FILE already exists, please either remove it or add parameters manually."
        exit 1
    fi

    # Overwrite
    sudo tee "$LIMITS_FILE" <<EOF
#
# Media Cloud limits
#

# Each process is limited up to ~34 GB of memory
mediacloud      hard    as            33554432

# Increase the max. open files limit
mediacloud      soft    nofile        65536
mediacloud      hard    nofile        65536
EOF

fi

echo "Done setting required kernel parameters via limits.conf."

