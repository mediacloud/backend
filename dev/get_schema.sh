#!/bin/bash
#
# Generate latest schema file for reference in development
#

set -u
set -e

docker pull dockermediacloud/postgresql-server:master
docker run dockermediacloud/postgresql-server:master cat /tmp/mediawords.sql > ./apps/postgresql-server/schema/mediawords.sql