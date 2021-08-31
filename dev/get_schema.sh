#!/bin/bash
#
# Generate latest schema file for reference in development 
#

set -u
set -e

PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

docker run gcr.io/mcback/postgresql-server:latest cat /opt/mediawords.sql > $PROJECT_ROOT/mediawords.sql