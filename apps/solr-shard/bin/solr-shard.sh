#!/bin/bash

set -e

if [ -z "$MC_SOLR_SHARD_COUNT" ]; then
    echo "MC_SOLR_SHARD_COUNT (total shard count) is not set."
    exit 1
fi

set -u

MC_SOLR_ZOOKEEPER_HOST="solr-zookeeper"
MC_SOLR_ZOOKEEPER_PORT=2181
MC_SOLR_PORT=8983

# Timeout in milliseconds at which Solr shard disconnects from ZooKeeper
MC_SOLR_ZOOKEEPER_TIMEOUT=30000

# <luceneMatchVersion> value
MC_SOLR_LUCENEMATCHVERSION="6.5.0"

# Make Solr use 90% of available RAM allotted to the container
MC_RAM_SIZE=$(/container_memory_limit.sh)
MC_SOLR_MX=$((MC_RAM_SIZE / 10 * 9))

# Wait for ZooKeeper container to show up
while true; do
    echo "Waiting for ZooKeeper to start..."
    if nc -z -w 10 solr-zookeeper 2181; then
        break
    else
        sleep 1
    fi
done

# Run Solr
java_args=(
    -server
    "-Xmx${MC_SOLR_MX}m"
    -Djava.util.logging.config.file=file:///var/lib/solr/resources/log4j.properties
    -Djetty.base=/var/lib/solr
    -Djetty.home=/var/lib/solr
    -Djetty.port="${MC_SOLR_PORT}"
    -Dsolr.solr.home=/var/lib/solr
    -Dsolr.data.dir=/var/lib/solr
    -Dsolr.log.dir=/var/lib/solr
    -Dhost="${HOSTNAME}"
    -DzkHost="${MC_SOLR_ZOOKEEPER_HOST}:${MC_SOLR_ZOOKEEPER_PORT}"
    -DnumShards="${MC_SOLR_SHARD_COUNT}"
    -DzkClientTimeout="${MC_SOLR_ZOOKEEPER_TIMEOUT}"
    -Dmediacloud.luceneMatchVersion="${MC_SOLR_LUCENEMATCHVERSION}"
    # Needed for resolving paths to JARs in solrconfig.xml
    -Dmediacloud.solr_dist_dir=/opt/solr
    -Dmediacloud.solr_webapp_dir=/opt/solr/server/solr-webapp
    # Remediate CVE-2017-12629
    -Ddisable.configEdit=true
    -jar start.jar
    --module=http
)
cd /var/lib/solr
exec java "${java_args[@]}"
