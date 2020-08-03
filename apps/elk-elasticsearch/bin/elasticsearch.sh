#!/bin/bash

set -e

if [ -z "$MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_ACCESS_KEY_ID" ]; then
    echo "MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_ACCESS_KEY_ID is not set."
    exit 1
fi

if [ -z "$MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_SECRET_ACCESS_KEY" ]; then
    echo "MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_SECRET_ACCESS_KEY is not set."
    exit 1
fi

if [ -z "$MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_BUCKET_NAME" ]; then
    echo "MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_BUCKET_NAME is not set."
    exit 1
fi

if [ -z "$MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_PATH_PREFIX" ]; then
    echo "MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_PATH_PREFIX is not set."
    exit 1
fi

set -u

# Update AWS credentials in a keystore
echo -n "$MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_ACCESS_KEY_ID" | \
    /opt/elasticsearch/bin/elasticsearch-keystore add s3.client.elk_logs.access_key --stdin --force
echo -n "$MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_SECRET_ACCESS_KEY" | \
    /opt/elasticsearch/bin/elasticsearch-keystore add s3.client.elk_logs.secret_key --stdin --force

if [ ! -f /var/lib/elasticsearch/s3-snapshots-setup ]; then
    echo "Setting up S3 snapshots on first run..."
    source /opt/elasticsearch/bin/setup_s3_snapshots.inc.sh
    echo "Done setting up S3 snapshots."
    touch /var/lib/elasticsearch/s3-snapshots-setup
fi

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
