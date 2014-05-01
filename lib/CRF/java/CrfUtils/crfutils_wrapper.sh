#!/bin/bash

# Die on error
set -e

PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

MC_ROOT="$PWD/../../../../"
QUERY_CONFIG="$MC_ROOT/script/run_with_carton.sh $MC_ROOT/script/mediawords_query_config.pl"

# 'cd' to where the Maven project resides (same location as the wrapper script)
cd "$PWD/"



log() {
    # to STDERR
    echo "$@" 1>&2
}

crf_web_service_is_enabled() {
    local crf_web_service_is_enabled=`$QUERY_CONFIG "//crf_web_service/enabled"`
    if [ "$crf_web_service_is_enabled" == "yes" ]; then
        return 0    # "true" in Bash
    else
        return 1    # "false" in Bash
    fi
}

maven_is_installed() {
    local path_to_mvn=$(which mvn)
    if [ -x "$path_to_mvn" ] ; then
        return 0    # "true" in Bash
    else
        return 1    # "false" in Bash
    fi
}

#
# ---
#

echo "Testing environment..."
if ! crf_web_service_is_enabled; then
    log "CRF model runner web service is not enabled."
    log "If you want to use CRF model runner web service instead of"
    log "Inline::Java in the extractor, please enable the service in"
    log "'mediawords.yml' by setting /crf_web_service/enabled to 'yes'."
    exit 0
fi

if ! maven_is_installed; then
    log "'mvn' was not found anywhere on your system."
    log "Please install Maven by running:"
    log ""
    log "    apt-get install maven"
    log ""
    exit 1
fi

echo "Reading configuration..."
CRF_LISTEN=`$QUERY_CONFIG "//crf_web_service/listen"`
CRF_NUMBER_OF_THREADS=`$QUERY_CONFIG "//crf_web_service/number_of_threads"`

MVN_PARAMS="compile exec:java"
if [[ ! -z "$CRF_LISTEN" ]]; then
    MVN_PARAMS="$MVN_PARAMS -Dcrf.httpListen=$CRF_LISTEN"
fi
MVN_PARAMS="$MVN_PARAMS -Dcrf.numberOfThreads=$CRF_NUMBER_OF_THREADS"

echo "Executing: mvn $MVN_PARAMS"
exec mvn $MVN_PARAMS
