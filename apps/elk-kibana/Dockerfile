#
# Kibana for ELK logging stack
#

FROM dockermediacloud/java-base:latest

# Install Kibana
# (https://www.elastic.co/downloads/kibana-oss)
ENV ELK_KIBANA_VERSION=7.8.1
RUN \
    mkdir -p /opt/kibana/ && \
    curl --fail --location --retry 3 --retry-delay 5 "https://artifacts.elastic.co/downloads/kibana/kibana-oss-${ELK_KIBANA_VERSION}-linux-x86_64.tar.gz" | \
        tar -zx -C /opt/kibana/ --strip 1 && \
    true

# Add unprivileged user the service will run as
RUN useradd -ms /bin/bash elk

# Fix permissions
RUN \
    mkdir -p /opt/kibana/config/ && \
    chown elk:elk /opt/kibana/data/ && \
    chown -R elk:elk /opt/kibana/optimize/ && \
    true

# Copy over configuration
COPY config/ /opt/kibana/config/
RUN \
    chown elk:elk /opt/kibana/config/ && \
    chmod go-w /opt/kibana/config/kibana.yml && \
    true

COPY bin/kibana.sh /opt/kibana/bin/

# Web server
EXPOSE 5601

USER elk

# Run Kibana via wrapper script
CMD ["/opt/kibana/bin/kibana.sh"]
