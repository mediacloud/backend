#!/bin/bash
#
# Generate latest schema file for reference in development 
#

set -u
set -e

docker pull gcr.io/mcback/postgresql-server:latest

PWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

exec "docker run gcr.io/mcback/postgresql-server:latest cat /tmp/mediawords.sql > $PWD/../apps/postgresql-server/schema/mediawords.sql"