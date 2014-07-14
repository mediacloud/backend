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
    if [ -x "$path_to_gearmand" ]; then
        return 0    # "true" in Bash
    else
        return 1    # "false" in Bash
    fi
}

gearmand_version() {
    local gearmand_version=`gearmand --version | perl -e '
        while (<>) {
            chomp;
            $version_string .= $_;
        }
        @parts = split(/ /, $version_string);
        print $parts[1]'`
        
    if [ -z "$gearmand_version" ]; then
        log "Unable to determine gearmand version"
        exit 1
    fi
    echo "$gearmand_version"
}

gearmand_is_up_to_date() {
    local gearmand_version=$(gearmand_version)
    echo "$gearmand_version" | perl -e '
        use version 0.77;
        $current_version = version->parse(<>);
        $required_version = version->parse("1.0.1");
        unless ($current_version >= $required_version) {
            die "Current gearmand version $current_version is older than required version $required_version\n";
        } else {
            print "Current gearmand version $current_version is up-to-date.\n";
        }' || {

        return 1    # "false" in Bash
    }
    return 0    # "true" in Bash
}

print_gearman_installation_instructions() {
    log "Please install Gearman by running:"
    log ""
    log "    sudo apt-get -y remove gearman gearman-job-server gearman-tools \\"
    log "        libgearman-dbg libgearman-dev libgearman-doc libgearman6"
    log "    sudo apt-get -y install python-software-properties"
    log "    sudo add-apt-repository -y ppa:gearman-developers/ppa"
    log "    sudo apt-get -y update"
    log "    sudo apt-get -y install gearman-job-server gearman-tools libgearman-dev"
    log ""
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
    log "'gearmand' was not found in your PATH."
    print_gearman_installation_instructions
    exit 1
fi

if ! gearmand_is_up_to_date; then
    log "'gearmand' was found in your PATH, but is too old."
    print_gearman_installation_instructions
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
