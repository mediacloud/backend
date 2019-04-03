#
# Solr ZooKeeper
# (Solr has integrated ZooKeeper instance itself but docs advise against using it in production)
#

# Uses Solr base image because ZooKeeper uploads Solr configuration to its instance
FROM dockermediacloud/mediacloud-solr-base:latest

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

# ZooKeeper data
VOLUME /var/lib/zookeeper/

# ZooKeeper client port
EXPOSE 2181

# ZooKeeper follower port
EXPOSE 2888

# ZooKeeper election port
EXPOSE 3888

# Run ZooKeeper
COPY bin/zookeeper.sh /

CMD ["/zookeeper.sh"]
