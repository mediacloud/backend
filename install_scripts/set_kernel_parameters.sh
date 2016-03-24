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

# Gearman::JobScheduler doesn't reuse existing TCP connections so under high
# load gearmand might run out of TCP connections.
net.ipv4.tcp_tw_reuse=1
EOF

    # Reread kernel parameters from /etc
    sudo service procps start

fi

echo "Done setting required kernel parameters via sysctl."
