#!/bin/bash

set -u
set -e

# Set up rsyslog for logging
source /rsyslog.inc.sh

# Copy environment variables to /etc/environment for the Cron jobs to be able to use them
printenv | grep -v '^HOME=' >> /etc/environment

# Run Cron in foreground
exec cron -f
