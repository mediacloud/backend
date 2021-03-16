#!/bin/bash

set -e
set -u

# https://www.elastic.co/guide/en/elasticsearch/reference/current/max-number-of-threads.html
if [ "$(ulimit -u)" != "unlimited" ] && [ $(ulimit -u) -lt 4096 ]; then
    echo "Process limit (ulimit -u) is too low."
    exit 1
fi

# https://www.elastic.co/guide/en/elasticsearch/reference/current/file-descriptors.html
if [ "$(ulimit -n -S)" != "unlimited" ] && [ $(ulimit -n -S) -lt 65535 ]; then
    echo "Soft open file limit (ulimit -n -S) is too low."
    exit 1
fi
if [ "$(ulimit -n -H)" != "unlimited" ] && [ $(ulimit -n -H) -lt 65535 ]; then
    echo "Hard open file limit (ulimit -n -H) is too low."
    exit 1
fi

# "Set Xmx and Xms to no more than 50% of your physical RAM."
MC_RAM_SIZE=$(/container_memory_limit.sh)
MC_ELASTICSEARCH_MS=$((MC_RAM_SIZE / 10 * 4))
MC_ELASTICSEARCH_MX="${MC_ELASTICSEARCH_MS}"

export ES_JAVA_OPTS=""

# Memory limits
export ES_JAVA_OPTS="${ES_JAVA_OPTS} -Xms${MC_ELASTICSEARCH_MS}m"
export ES_JAVA_OPTS="${ES_JAVA_OPTS} -Xmx${MC_ELASTICSEARCH_MX}m"

# Run Elasticsearch
exec /opt/elasticsearch/bin/elasticsearch
