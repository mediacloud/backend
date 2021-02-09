#
# Filebeat for ELK file + container logging
#

FROM gcr.io/mcback/base:latest

# Install Filebeat
# (https://www.elastic.co/downloads/beats/filebeat)
ENV ELK_FILEBEAT_VERSION=7.10.2
RUN \
    mkdir -p /opt/filebeat/ && \
    curl --fail --location --retry 3 --retry-delay 5 "https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${ELK_FILEBEAT_VERSION}-linux-x86_64.tar.gz" | \
        tar -zx -C /opt/filebeat/ --strip 1 && \
    true

# Add unprivileged user the service will run as
# RUN useradd -ms /bin/bash elk

# Copy over configuration
COPY filebeat.yml /opt/filebeat/
COPY filebeat-ilm.json /opt/filebeat/
RUN \
    # chown elk:elk /opt/filebeat/filebeat.yml && \
    chmod go-w /opt/filebeat/filebeat.yml && \
    true

# Copy worker wrapper
COPY filebeat.sh /opt/filebeat/
RUN chmod +x /opt/filebeat/filebeat.sh

# Create data directory
RUN \
    mkdir /opt/filebeat/data/ && \
    # chown elk:elk /opt/filebeat/data/ && \
    true

# USER elk

# Create keystore
WORKDIR /opt/filebeat/
RUN \
    /opt/filebeat/filebeat -e keystore create && \
    # chown elk:elk /opt/filebeat/data/filebeat.keystore && \
    true

# Test configuration
RUN /opt/filebeat/filebeat -E name=$(cat /etc/hostname) test config -e

# No VOLUME as Filebeat's data is (probably) transient

# Run Filebeat via wrapper script
CMD ["/opt/filebeat/filebeat.sh"]
