#!/bin/bash

set -u
set -e

export MC_TEMPORAL_POSTGRESQL_HOST="temporal-postgresql"

# Hostname for binding configuration
export MC_TEMPORAL_HOST_IP=$(hostname -i)

# Generate final config
envsubst \
    < /opt/temporal-server/config/mediacloud_template.yaml \
    > /opt/temporal-server/config/mediacloud.yaml

# FIXME give up and crash after a while

while true; do
    echo "Waiting for PostgreSQL to start..."
    if nc -z -w 10 temporal-postgresql 5432; then
        break
    else
        sleep 1
    fi
done

while true; do
    echo "Waiting for Elasticsearch to start..."
    if curl --silent --show-error --fail "http://temporal-elasticsearch:9200/_cluster/health"; then
        break
    else
        sleep 1
    fi
done

# FIXME perhaps run all four services ("frontend", "history", "matching", "worker")
# as separate containers?
exec temporal-server \
    --root /opt/temporal-server \
    --env mediacloud \
    start
