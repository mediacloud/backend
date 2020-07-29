#!/bin/bash

set -e

# Make Logstash use 50% of available RAM allotted to the container
# (https://www.elastic.co/guide/en/logstash/current/jvm-settings.html#heap-size)
MC_RAM_SIZE=$(/container_memory_limit.sh)
MC_LOGSTASH_MS=$((MC_RAM_SIZE / 10 * 6))
MC_LOGSTASH_MX=$MC_LOGSTASH_MS

export LS_JAVA_OPTS=""

# Memory limits
export LS_JAVA_OPTS="${LS_JAVA_OPTS} -Xms${MC_LOGSTASH_MS}m"
export LS_JAVA_OPTS="${LS_JAVA_OPTS} -Xmx${MC_LOGSTASH_MX}m"

exec /opt/logstash/bin/logstash \
    --pipeline.workers $(/container_cpu_limit.sh)
