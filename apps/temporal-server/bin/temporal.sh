#!/bin/bash

set -u
set -e

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

register_default_namespace() {
    echo "Registering default namespace: $DEFAULT_NAMESPACE"
    until tctl --ns default namespace describe < /dev/null; do
        echo "Default namespace not found. Creating..."
        sleep 1
        # FIXME doesn't work
        # FIXME retention period super short
        tctl --ns default namespace register --rd 1 --desc "Default namespace for Temporal Server" || echo "Creating default namespace failed."
    done
    echo "Default namespace registration complete."
}

if [ -e /var/lib/temporal/first_run ]; then
    echo "Registering default namespace on first run..."
    # FIXME not that great to run it in the background
    register_default_namespace &
    rm /var/lib/temporal/first_run
fi

exec temporal-server \
    --root /opt/temporal-server \
    --env mediacloud \
    start
