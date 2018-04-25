#
# Solr ZooKeeper
#

# Uses Solr base image because ZooKeeper uploads Solr configuration to its instance
FROM mediacloud-solr-base:latest

# ZooKeeper version
ENV MEDIACLOUD_ZOOKEEPER_VERSION "3.4.10"

# Download and extract ZooKeeper
RUN \
    curl -L "https://archive.apache.org/dist/zookeeper/zookeeper-${MEDIACLOUD_ZOOKEEPER_VERSION}/zookeeper-${MEDIACLOUD_ZOOKEEPER_VERSION}.tar.gz" \
        > /var/tmp/zookeeper.tgz && \
    mkdir -p /opt/zookeeper/ && \
    tar -zxf /var/tmp/zookeeper.tgz -C /opt/zookeeper --strip 1 && \
    rm /var/tmp/zookeeper.tgz
