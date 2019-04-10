#!/bin/bash

set -u
set -e

# Docker doesn't understand case randomisation:
# https://github.com/pgbouncer/pgbouncer/issues/122#issuecomment-343962394
echo "options randomize-case:0" >> /etc/resolv.conf

exec sudo su - postgres /bin/bash -c '/usr/sbin/pgbouncer -v /etc/pgbouncer/pgbouncer.ini'
