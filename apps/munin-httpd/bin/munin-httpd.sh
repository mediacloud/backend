#!/bin/bash

set -e

# Make sure "munin" user is able to write to STDOUT / STDERR
# (https://github.com/moby/moby/issues/31243#issuecomment-406879017)
chmod 666 /dev/stdout /dev/stderr

exec lighttpd -D -f /etc/lighttpd/lighttpd.conf
