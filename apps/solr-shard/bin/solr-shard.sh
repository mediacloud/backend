#!/bin/bash
#
# Run Solr shard
#

MC_SOLR_ZOOKEEPER_HOST="mc_solr_zookeeper"
MC_SOLR_ZOOKEEPER_PORT=2181
MC_SOLR_PORT=8983

# Timeout in milliseconds at which Solr shard disconnects from ZooKeeper
MC_SOLR_ZOOKEEPER_TIMEOUT=300000

# <luceneMatchVersion> value
MC_SOLR_LUCENEMATCHVERSION="6.5.0"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 number_of_shards"
    exit 1
fi

MC_NUM_SHARDS=$1
if [ $MC_NUM_SHARDS -lt 1 ]; then
    echo "Number of shards must be positive."
    exit 1
fi

# Copy Solr distribution to data directory
cp -R /opt/solr/server/* /var/lib/solr/

# Copy Solr configuration to data directory
# (some Solr distribution files from the previous stem might get overwritten)
cp -R /usr/src/solr/* /var/lib/solr/

# Make Solr use 90% of available RAM allotted to the container
MC_RAM_SIZE=$(/container_memory_limit.sh)
MC_SOLR_MX=$((MC_RAM_SIZE / 10 * 9))

# Run Solr
java_args=(
    -server
    "-Xmx${MC_SOLR_MX}m"
    -Djava.util.logging.config.file=file:///var/lib/solr/resources/log4j.properties
    -Djetty.base=/var/lib/solr
    -Djetty.home=/var/lib/solr
    -Djetty.port=$MC_SOLR_PORT
    -Dsolr.solr.home=/var/lib/solr
    -Dsolr.data.dir=/var/lib/solr
    -Dsolr.log.dir=/var/lib/solr
    -Dhost=$HOSTNAME
    -DzkHost="${MC_SOLR_ZOOKEEPER_HOST}:${MC_SOLR_ZOOKEEPER_PORT}"
    -DnumShards=$MC_NUM_SHARDS
    -DzkClientTimeout=$MC_SOLR_ZOOKEEPER_TIMEOUT
    -Dmediacloud.luceneMatchVersion=$MC_SOLR_LUCENEMATCHVERSION
    # Enable heap dumps on OOMs:
    -XX:+HeapDumpOnOutOfMemoryError
    -XX:HeapDumpPath=/var/lib/solr
    # Use cgroup's memory / CPU limits
    -XX:+UseContainerSupport
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
