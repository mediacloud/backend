#!/bin/bash

set -e

# "Set Xmx and Xms to no more than 50% of your physical RAM."
MC_RAM_SIZE=$(/container_memory_limit.sh)
MC_ELASTICSEARCH_MS=$((MC_RAM_SIZE / 10 * 4))
MC_ELASTICSEARCH_MX=$MC_ELASTICSEARCH_MS

export ES_JAVA_OPTS=""

# Memory limits
export ES_JAVA_OPTS="${ES_JAVA_OPTS} -Xms${MC_ELASTICSEARCH_MS}m"
export ES_JAVA_OPTS="${ES_JAVA_OPTS} -Xmx${MC_ELASTICSEARCH_MX}m"

# Run Elasticsearch
exec /opt/elasticsearch/bin/elasticsearch
