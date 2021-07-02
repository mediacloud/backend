#!/bin/bash

set -u
set -e


echo "Starting Elasticsearch for index setup..."
/opt/elasticsearch/bin/elasticsearch &

for i in {1..120}; do
    echo "Waiting for Elasticsearch to start..."
    if curl --silent --show-error --fail "http://127.0.0.1:9200/_cluster/health"; then
        break
    else
        sleep 1
    fi
done


echo "Creating Temporal index template..."
curl -XPUT "http://127.0.0.1:9200/_template/temporal-visibility-template" \
    --fail \
    --silent \
    --show-error \
    -H "Content-Type: application/json" \
    -d @index_template.json
echo "Done creating Temporal index template."


echo "Stopping Elasticsearch..."
killall java
while pgrep java > /dev/null; do
    sleep 0.5
done
