#!/bin/bash

# Die on error
set -e

# 'cd' to Media Cloud's root (assuming that this script is stored in './script/')
PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$PWD/../"

log() {
    # to STDERR
    echo "$@" 1>&2
}

gearmand_is_enabled() {
    local gearmand_is_enabled=`./script/run_with_carton.sh ./script/mediawords_query_config.pl //gearmand/enabled`
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

# Read PostgreSQL configuration from mediawords.yml
# (scope of the following exports is local)
export PGHOST=`./script/run_with_carton.sh ./script/mediawords_query_config.pl "//database[label!='test']/host"`
export PGPORT=5432
export PGUSER=`./script/run_with_carton.sh ./script/mediawords_query_config.pl "//database[label!='test']/user"`
export PGPASSWORD=`./script/run_with_carton.sh ./script/mediawords_query_config.pl "//database[label!='test']/pass"`
export PGDATABASE="mediacloud_gearman"

GEARMAND_PARAMS=""
GEARMAND_PARAMS="$GEARMAND_PARAMS --listen=127.0.0.1"
GEARMAND_PARAMS="$GEARMAND_PARAMS --port=4731"
GEARMAND_PARAMS="$GEARMAND_PARAMS --queue-type Postgres"
GEARMAND_PARAMS="$GEARMAND_PARAMS --libpq-table=queue"
GEARMAND_PARAMS="$GEARMAND_PARAMS --verbose INFO"
GEARMAND_PARAMS="$GEARMAND_PARAMS --log-file stderr"

gearmand $GEARMAND_PARAMS
