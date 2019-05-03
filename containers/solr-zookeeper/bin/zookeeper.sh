#!/bin/bash
#
# Run ZooKeeper
#

set -u
set -e

# Set configuration
export ZOOCFGDIR=/opt/zookeeper/conf    # no slash at the end
export ZOOCFG=zoo.cfg
export ZOO_LOG_DIR=/var/lib/zookeeper   # no slash at the end
export SERVER_JVMFLAGS="-Dlog4j.configuration=file:///opt/zookeeper/conf/log4j.properties"


# Start a temporary instance of ZooKeeper to upload config
# (started listening to localhost only and on a different port for the clients
# to think that ZooKeeper is fully up and running)
TEMP_PORT=12345
TEMP_CONFIG=zoo-setup.cfg
TEMP_CONFIG_PATH="$ZOOCFGDIR/$TEMP_CONFIG"
cp "$ZOOCFGDIR/$ZOOCFG" "$TEMP_CONFIG_PATH"
sed -i -e "s/^clientPortAddress=.*/clientPortAddress=127.0.0.1/" $TEMP_CONFIG_PATH
sed -i -e "s/^clientPort=.*/clientPort=$TEMP_PORT/" $TEMP_CONFIG_PATH
ZOOCFG="$TEMP_CONFIG" /opt/zookeeper/bin/zkServer.sh start-foreground &
while true; do
    echo "Waiting for ZooKeeper to start..."
    if nc -z -w 10 127.0.0.1 $TEMP_PORT; then
        break
    else
        sleep 1
    fi
done

# Upload Solr collections
for collection_path in /usr/src/solr/collections/*; do
    if [ -d $collection_path ]; then
        # Looks like it's a collection?
        if [ -f "$collection_path/conf/solrconfig.xml" ]; then

            collection_name=`basename $collection_path`
            echo "Uploading and linking collection $collection_name..."

            /opt/solr/server/scripts/cloud-scripts/zkcli.sh \
                -zkhost 127.0.0.1:$TEMP_PORT \
                -cmd upconfig \
                -confdir "$collection_path/conf/" \
                -confname "$collection_name"

            /opt/solr/server/scripts/cloud-scripts/zkcli.sh \
                -zkhost 127.0.0.1:$TEMP_PORT \
                -cmd linkconfig \
                -collection "$collection_name" \
                -confname "$collection_name"
        fi
    fi
done

# Stop after initial configuration
pkill java

# Remove temporary configuration
rm "$TEMP_CONFIG_PATH"

# Run ZooKeeper normally
exec /opt/zookeeper/bin/zkServer.sh start-foreground
