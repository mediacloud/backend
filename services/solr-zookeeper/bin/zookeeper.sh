#!/bin/bash
#
# Run ZooKeeper
#

set -u
set -e

# Set configuration
export ZOOCFGDIR=/var/lib/zookeeper/
export ZOOCFG=zoo.cfg
export ZOO_LOG_DIR=/var/lib/zookeeper/
export SERVER_JVMFLAGS="-Dlog4j.configuration=file:///opt/zookeeper/conf/log4j.properties"


# Start ZooKeeper, wait for it to start up
/opt/zookeeper/bin/zkServer.sh start-foreground &
while true; do
    echo "Waiting for ZooKeeper to start..."
    if nc -z -w 10 127.0.0.1 2181; then
        break
    else
        sleep 1
    fi
done

# Upload Solr collections
for collection_path in /usr/src/solr/collections/*; do
    if [ -d $collection_path ]; then

        collection_name=`basename $collection_path`
        echo "Uploading and linking collection $collection_name..."

        /opt/solr/server/scripts/cloud-scripts/zkcli.sh \
            -zkhost 127.0.0.1:2181 \
            -cmd upconfig \
            -confdir "$collection_path/conf/" \
            -confname "$collection_name"

        /opt/solr/server/scripts/cloud-scripts/zkcli.sh \
            -zkhost 127.0.0.1:2181 \
            -cmd linkconfig \
            -collection "$collection_name" \
            -confname "$collection_name"
    fi
done

# Stop after initial configuration
pkill java

# Run ZooKeeper normally
exec /opt/zookeeper/bin/zkServer.sh start-foreground
