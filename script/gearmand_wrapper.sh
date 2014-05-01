#!/bin/bash

# Die on error
set -e

PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

QUERY_CONFIG="$PWD/../script/run_with_carton.sh $PWD/../script/mediawords_query_config.pl"

# 'cd' to Media Cloud's root (assuming that this script is stored in './script/')
cd "$PWD/../"



log() {
    # to STDERR
    echo "$@" 1>&2
}

gearmand_is_enabled() {
    local gearmand_is_enabled=`$QUERY_CONFIG "//gearmand/enabled"`
    if [ "$gearmand_is_enabled" == "yes" ]; then
        return 0    # "true" in Bash
    else
        return 1    # "false" in Bash
    fi
}

gearmand_is_installed() {
    local path_to_gearmand=$(which gearmand)
    if [ -x "$path_to_gearmand" ] ; then
        return 0    # "true" in Bash
    else
        return 1    # "false" in Bash
    fi
}

#
# ---
#

echo "Testing environment..."
if ! gearmand_is_enabled; then
    log "'gearmand' is not enabled."
    log "Please enable it in 'mediawords.yml' by setting /gearmand/enabled to 'yes'."
    exit 0
fi

if ! gearmand_is_installed; then
    log "'gearmand' was not found anywhere on your system."
    log "Please install 'gearmand' by running:"
    log ""
    log "    apt-get install gearman"
    log ""
    exit 1
fi

echo "Reading configuration..."
# Read PostgreSQL configuration from mediawords.yml
# (scope of the following exports is local)
export PGHOST=`$QUERY_CONFIG "//database[label='gearman']/host"`
PGPORT=`$QUERY_CONFIG "//database[label='gearman']/port" 2> /dev/null || echo -n`
if [[ -z "$PGPORT" ]]; then
    PGPORT=5432
fi
export PGPORT="$PGPORT"
export PGUSER=`$QUERY_CONFIG "//database[label='gearman']/user"`
export PGPASSWORD=`$QUERY_CONFIG "//database[label='gearman']/pass"`
export PGDATABASE=`$QUERY_CONFIG "//database[label='gearman']/db"`

GEARMAN_LISTEN=`$QUERY_CONFIG "//gearmand/listen"`
GEARMAN_PORT=`$QUERY_CONFIG "//gearmand/port"`

GEARMAND_PARAMS=""
if [[ ! -z "$GEARMAN_LISTEN" ]]; then
    GEARMAND_PARAMS="$GEARMAND_PARAMS --listen=$GEARMAN_LISTEN"
fi
GEARMAND_PARAMS="$GEARMAND_PARAMS --port=$GEARMAN_PORT"
GEARMAND_PARAMS="$GEARMAND_PARAMS --queue-type Postgres"
GEARMAND_PARAMS="$GEARMAND_PARAMS --libpq-table=queue"
GEARMAND_PARAMS="$GEARMAND_PARAMS --verbose INFO"
GEARMAND_PARAMS="$GEARMAND_PARAMS --log-file stderr"

echo "Executing: gearmand $GEARMAND_PARAMS"
exec gearmand $GEARMAND_PARAMS
