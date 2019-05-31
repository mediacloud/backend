#
# Solr ZooKeeper
# (Solr has integrated ZooKeeper instance itself but docs advise against using it in production)
#

# Uses Solr base image because ZooKeeper uploads Solr configuration to its instance
FROM dockermediacloud/solr-base:latest

# ZooKeeper version
ENV MEDIACLOUD_ZOOKEEPER_VERSION "3.4.10"

# Download and extract ZooKeeper
RUN \
    curl -L "https://archive.apache.org/dist/zookeeper/zookeeper-${MEDIACLOUD_ZOOKEEPER_VERSION}/zookeeper-${MEDIACLOUD_ZOOKEEPER_VERSION}.tar.gz" \
        > /var/tmp/zookeeper.tgz && \
    mkdir -p /opt/zookeeper/ && \
    tar -zxf /var/tmp/zookeeper.tgz -C /opt/zookeeper --strip 1 && \
    rm /var/tmp/zookeeper.tgz

# Copy configuration
COPY conf/zoo.cfg /opt/zookeeper/conf/

# Pre-initialize with Solr configuration
COPY bin/init_solr_config.sh /
RUN \
    /init_solr_config.sh && \
    #
    # Move the "clean" ZooKeeper data directory to /var/lib/zookeeper-template/
    # so that we could use a clean data directory (e.g. without Solr hostnames
    # hardcoded) on every ZooKeeper start.
    #
    # We don't preserve ZooKeeper data volume because Solr shard hostnames keep
    # on changing constantly so it's more painful than useful to make ZooKeeper
    # figure out that said hostnames have changed - faster way is just to let
    # ZooKeeper reread locations of shards on every start.
    mv /var/lib/zookeeper/ /var/lib/zookeeper-template/ && \
    #
    true

# Copy wrapper script
COPY bin/zookeeper.sh /

# ZooKeeper client port
EXPOSE 2181

# ZooKeeper follower port
EXPOSE 2888

# ZooKeeper election port
EXPOSE 3888

# Start ZooKeeper
CMD ["/zookeeper.sh"]
