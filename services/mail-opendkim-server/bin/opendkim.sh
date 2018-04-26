#!/bin/bash

set -u
set -e

# Set up rsyslog for logging
source /rsyslog.inc.sh

# Start OpenDKIM
exec opendkim \
    -f \
    -v \
    -x /etc/opendkim.conf \
    -u opendkim \
    -P /var/run/opendkim/opendkim.pid \
    -p inet:12301@localhost
