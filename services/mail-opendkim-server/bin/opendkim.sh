#!/bin/bash

set -u
set -e

# Symlink syslog to Docker's STDOUT
rm -f /var/log/syslog
ln -s /dev/fd/1 /var/log/syslog
chmod 666 /var/log/syslog

# Start rsyslogd
rsyslogd -n &

# Start OpenDKIM
exec opendkim \
    -f \
    -v \
    -x /etc/opendkim.conf \
    -u opendkim \
    -P /var/run/opendkim/opendkim.pid \
    -p inet:12301@localhost
