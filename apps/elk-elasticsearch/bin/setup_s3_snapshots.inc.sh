set -e


if [ -z "$MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_BUCKET_NAME" ]; then
    echo "MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_BUCKET_NAME is not set."
    exit 1
fi

if [ -z "$MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_PATH_PREFIX" ]; then
    echo "MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_PATH_PREFIX is not set."
    exit 1
fi


set -u


ES_TEMP_PORT=12345


# Start ES on a non-public port so that the clients don't attempt to connect yet
echo "Starting Elasticsearch for snapshot setup..."
/opt/elasticsearch/bin/elasticsearch -E http.port="${ES_TEMP_PORT}" -E transport.port=12346 &

for i in {1..120}; do
    echo "Waiting for Elasticsearch to start..."
    if curl --fail "http://127.0.0.1:${ES_TEMP_PORT}/_cluster/health"; then
        break
    else
        sleep 1
    fi
done


echo "Creating S3 snapshot repository..."
cat << EOF > /var/tmp/create-repository.json
{
    "type": "s3",
    "settings": {
        "bucket": "${MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_BUCKET_NAME}",
        "base_path": "${MC_ELK_ELASTICSEARCH_SNAPSHOT_S3_PATH_PREFIX}",
        "client": "elk_logs"
    }
}
EOF
curl -XPUT "http://127.0.0.1:${ES_TEMP_PORT}/_snapshot/elk_logs" \
    --fail \
    -H "Content-Type: application/json" \
    -d @/var/tmp/create-repository.json
rm /var/tmp/create-repository.json
echo "Done creating S3 snapshot repository."


echo "Creating nightly snapshot policy..."
cat << EOF > /var/tmp/create-policy.json
{
    "schedule": "0 30 1 * * ?",
    "name": "<nightly-{now/d}>",
    "repository": "elk_logs",
    "config": {
        "indices": ["*"]
    },
    "retention": {
        "expire_after": "365d"
    }
}
EOF
curl -XPUT "http://127.0.0.1:${ES_TEMP_PORT}/_slm/policy/nightly-s3-snapshots" \
    --fail \
    -H "Content-Type: application/json" \
    -d @/var/tmp/create-policy.json
rm /var/tmp/create-policy.json
echo "Done creating nightly snapshot policy."


# Enable querying multiple indices at once (via the "*"" index pattern)
echo "Storing per-index configuration..."
cat << EOF > /var/tmp/per-index-config.json
{
  "index.max_docvalue_fields_search" : "200"
}
EOF
curl -XPUT "http://127.0.0.1:${ES_TEMP_PORT}/_all/_settings?preserve_existing=true" \
    --fail \
    -H "Content-Type: application/json" \
    -d @/var/tmp/per-index-config.json
rm /var/tmp/per-index-config.json
echo "Done storing per-index configuration."


echo "Stopping Elasticsearch after snapshot setup..."
killall java
while pgrep java > /dev/null; do
    sleep 0.5
done
