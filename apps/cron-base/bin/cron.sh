#!/bin/bash

set -u
set -e

# Set up rsyslog for logging
source /rsyslog.inc.sh

# Run Cron in foreground
exec cron -f
