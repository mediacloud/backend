#
# Logstash for ELK logging stack
#

FROM dockermediacloud/java-base:latest

# Install Logstash
# (https://www.elastic.co/downloads/logstash-oss)
ENV ELK_LOGSTASH_VERSION=7.7.1
RUN \
    mkdir -p /opt/logstash/ && \
    curl --fail --location --retry 3 --retry-delay 5 "https://artifacts.elastic.co/downloads/logstash/logstash-oss-${ELK_LOGSTASH_VERSION}.tar.gz" | \
        tar -zx -C /opt/logstash/ --strip 1 && \
    true

# Add unprivileged user the service will run as
RUN useradd -ms /bin/bash elk

# Copy data directory, fix permissions
COPY data/ /opt/logstash/data/
RUN \
    chown -R elk:elk /opt/logstash/data/ && \
    chown -R elk:elk /opt/logstash/config/ && \
    rm /opt/logstash/config/* && \
    true

COPY config/* /opt/logstash/config/
COPY bin/logstash.sh /opt/logstash/bin/logstash.sh

# Beats log ingestion
EXPOSE 5044

# Metrics REST endpoint
EXPOSE 9600

USER elk

# Create keystore
WORKDIR /opt/logstash/
ENV LOGSTASH_KEYSTORE_PASS=mediacloud
RUN \
    /opt/logstash/bin/logstash-keystore create && \
    chown elk:elk /opt/logstash/config/logstash.keystore && \
    true

# Test configuration and create queue directories
RUN /opt/logstash/bin/logstash --config.test_and_exit

# Persistent data
VOLUME /opt/logstash/data/

# Run Logstash via wrapper script
CMD ["/opt/logstash/bin/logstash.sh"]
