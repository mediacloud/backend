#!/bin/bash

# Die on error
set -e

# Configuration
POM_PATH="local/lib/perl5/Mallet/java/CrfUtils/pom.xml"
CRF_EXTRACTOR_MODEL_PATH="lib/MediaWords/Util/models/crf_extractor_model"

PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

MC_ROOT="$PWD/../"
QUERY_CONFIG="$MC_ROOT/script/run_with_carton.sh $MC_ROOT/script/mediawords_query_config.pl"

cd "$MC_ROOT"


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

if [ ! -f "$CRF_EXTRACTOR_MODEL_PATH" ]; then
    log "Extractor model at path:"
    log ""
    log "    $CRF_EXTRACTOR_MODEL_PATH"
    log ""
    log "is unavailable."
    exit 1
fi

if [ ! -f "$POM_PATH" ]; then
    log "Maven POM file at path:"
    log ""
    log "    $POM_PATH"
    log ""
    log "is unavailable."
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
MVN_PARAMS="$MVN_PARAMS -Dcrf.extractorModelPath=$CRF_EXTRACTOR_MODEL_PATH"

echo "Executing: mvn $MVN_PARAMS"
cd "$MC_ROOT/"
exec mvn -f "$POM_PATH" $MVN_PARAMS
