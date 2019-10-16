#!/bin/bash

set -u
set -e

while [ ! -f /var/lib/munin/datafile ]; do
    echo "Waiting for Munin datafile to get created by munin-cron..."
    sleep 1
done

echo "Starting FastCGI worker..."
exec spawn-fcgi -n -p 22334 -U munin -u munin -g munin -- /usr/lib/munin/cgi/munin-cgi-graph --debug
