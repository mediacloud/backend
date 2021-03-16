#
# Base image for Elasticsearch
#

FROM gcr.io/mcback/java-base:latest

# Install Elasticsearch
# (https://www.elastic.co/downloads/elasticsearch-no-jdk)
ENV MC_ELASTICSEARCH_VERSION=7.10.2
RUN \
    mkdir -p /opt/elasticsearch/ && \
    curl --fail --location --retry 3 --retry-delay 5 "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${MC_ELASTICSEARCH_VERSION}-no-jdk-linux-x86_64.tar.gz" | \
        tar -zx -C /opt/elasticsearch/ --strip 1 && \
    true

# Add unprivileged user the service will run as
RUN useradd -ms /bin/bash elasticsearch

RUN \
    #
    # Data directory
    mkdir -p /var/lib/elasticsearch/ && \
    mkdir -p /var/lib/elasticsearch/jvm-heapdumps/ && \
    mkdir -p /var/lib/elasticsearch/jvm-gc-logs/ && \
    chown -R elasticsearch:elasticsearch /var/lib/elasticsearch/ && \
    #
    # JVM options directory
    mkdir -p /opt/elasticsearch/config/jvm.options.d/ && \
    chmod 775 /opt/elasticsearch/config/jvm.options.d/ && \
    #
    true

COPY config/* /opt/elasticsearch/config/
COPY bin/* /opt/elasticsearch/bin/

# Create keystore and move it to data volume
RUN \
    rm -f /opt/elasticsearch/config/elasticsearch.keystore && \
    rm -f /var/lib/elasticsearch/elasticsearch.keystore && \
    /opt/elasticsearch/bin/elasticsearch-keystore create && \
    mv /opt/elasticsearch/config/elasticsearch.keystore /var/lib/elasticsearch/ && \
    ln -s /var/lib/elasticsearch/elasticsearch.keystore /opt/elasticsearch/config/elasticsearch.keystore && \
    chown elasticsearch:elasticsearch /var/lib/elasticsearch/elasticsearch.keystore && \
    #
    # Keystore tool will want to write a "temporary" keystore:
    #
    #     ERROR: unable to create temporary keystore at
    #     [/opt/elasticsearch/config/elasticsearch.keystore.tmp],
    #     write permissions required for [/opt/elasticsearch/config]
    #     or run [elasticsearch-keystore upgrade]
    #
    # Plus the S3 plugin insists at writing to other locations too.
    #
    chown -R elasticsearch:elasticsearch /opt/elasticsearch/config/ && \
    #
    true

USER elasticsearch

# Elasticsearch HTTP
EXPOSE 9200

# Elasticsearch TCP transport
EXPOSE 9300

# Elasticsearch data
VOLUME /var/lib/elasticsearch

CMD ["/opt/elasticsearch/bin/elasticsearch.sh"]
