#!/bin/bash

set -u
set -e

# Make sure "munin" user is able to write to STDOUT / STDERR
# (https://github.com/moby/moby/issues/31243#issuecomment-406879017)
chmod 666 /var/log/munin/*.log

# Run "munin-cron"
exec sudo -u munin bash -c "/usr/bin/munin-cron --debug"
