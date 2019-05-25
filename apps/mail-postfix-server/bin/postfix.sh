#!/bin/bash

set -u
set -e

# Set up rsyslog for logging
source /rsyslog.inc.sh

# Start Postfix
exec /usr/lib/postfix/sbin/master -c /etc/postfix -d
