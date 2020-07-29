#
# Elasticsearch for ELK logging stack
#

FROM dockermediacloud/java-base:latest

# Install Elasticsearch
# (https://www.elastic.co/downloads/elasticsearch-oss-no-jdk)
ENV ELK_ELASTICSEARCH_VERSION=7.7.1
RUN \
    mkdir -p /opt/elasticsearch/ && \
    curl --fail --location --retry 3 --retry-delay 5 "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-oss-${ELK_ELASTICSEARCH_VERSION}-no-jdk-linux-x86_64.tar.gz" | \
        tar -zx -C /opt/elasticsearch/ --strip 1 && \
    true

# Add unprivileged user the service will run as
RUN useradd -ms /bin/bash elk

RUN \
    #
    # Data directory
    mkdir -p /var/lib/elasticsearch/ && \
    mkdir -p /var/lib/elasticsearch/jvm-heapdumps/ && \
    mkdir -p /var/lib/elasticsearch/jvm-gc-logs/ && \
    chown -R elk:elk /var/lib/elasticsearch/ && \
    #
    # JVM options directory
    mkdir -p /opt/elasticsearch/config/jvm.options.d/ && \
    chmod 775 /opt/elasticsearch/config/jvm.options.d/ && \
    #
    true

COPY config/* /opt/elasticsearch/config/
COPY bin/elasticsearch.sh /opt/elasticsearch/bin/

# Create keystore and move it to data volume
RUN \
    rm -f /opt/elasticsearch/config/elasticsearch.keystore && \
    /opt/elasticsearch/bin/elasticsearch-keystore create && \
    mv /opt/elasticsearch/config/elasticsearch.keystore /var/lib/elasticsearch/ && \
    ln -s /var/lib/elasticsearch/elasticsearch.keystore /opt/elasticsearch/config/elasticsearch.keystore && \
    chown elk:elk /var/lib/elasticsearch/elasticsearch.keystore && \
    true

USER elk

# Elasticsearch HTTP
EXPOSE 9200

# Elasticsearch TCP transport
EXPOSE 9300

# Elasticsearch data
VOLUME /var/lib/elasticsearch

CMD ["/opt/elasticsearch/bin/elasticsearch.sh"]
