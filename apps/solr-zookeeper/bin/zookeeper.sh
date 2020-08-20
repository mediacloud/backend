#!/bin/bash

set -u
set -e

# Configure ZooKeeper
export ZOOCFGDIR=/opt/zookeeper/conf    # no slash at the end
export ZOOCFG=zoo.cfg
export ZOO_LOG_DIR=/var/lib/zookeeper   # no slash at the end

export SERVER_JVMFLAGS=""

# Custom logging configuration
export SERVER_JVMFLAGS="${SERVER_JVMFLAGS} -Dlog4j.configuration=file:///opt/zookeeper/conf/log4j.properties"

#
# Cache DNS only for a second to be able to resolve new IPs of shards and
# ZooKeeper if they change
#
# FIXME: replace with networkaddress.cache.ttl and
# networkaddress.cache.negative.ttl properties
#
export SERVER_JVMFLAGS="${SERVER_JVMFLAGS} -Dsun.net.inetaddr.ttl=10"
export SERVER_JVMFLAGS="${SERVER_JVMFLAGS} -Dsun.net.inetaddr.negative.ttl=10"


if [ ! -d /var/lib/zookeeper-template/ ]; then
    echo "ZooKeeper template data directory does not exist."
    exit 1
fi

if [ ! -d /var/lib/zookeeper/ ]; then
    echo "ZooKeeper data directory does not exist."
    exit 1
fi

if [ ! -z "$(ls -A /var/lib/zookeeper/)" ]; then
	rm -rf /var/lib/zookeeper/*
fi

cp -R /var/lib/zookeeper-template/* /var/lib/zookeeper/

exec /opt/zookeeper/bin/zkServer.sh start-foreground
