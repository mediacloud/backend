#
# Journalbeat for ELK journald logging
#

FROM gcr.io/mcback/base:latest

# Install systemd to get journalctl utility
RUN apt-get -y --no-install-recommends install systemd

# Install Journalbeat
# (https://www.elastic.co/downloads/beats/journalbeat)
ENV ELK_JOURNALBEAT_VERSION=7.10.2
RUN \
    mkdir -p /opt/journalbeat/ && \
    curl --fail --location --retry 3 --retry-delay 5 "https://artifacts.elastic.co/downloads/beats/journalbeat/journalbeat-${ELK_JOURNALBEAT_VERSION}-linux-x86_64.tar.gz" | \
        tar -zx -C /opt/journalbeat/ --strip 1 && \
    true

# Add unprivileged user the service will run as
# RUN useradd -ms /bin/bash elk

# Copy over configuration
COPY journalbeat.yml /opt/journalbeat/
COPY journalbeat-ilm.json /opt/journalbeat/
RUN \
    # chown elk:elk /opt/journalbeat/journalbeat.yml && \
    chmod go-w /opt/journalbeat/journalbeat.yml && \
    true

# Copy worker wrapper
COPY journalbeat.sh /opt/journalbeat/
RUN chmod +x /opt/journalbeat/journalbeat.sh

# Create data directory
RUN \
    mkdir /opt/journalbeat/data/ && \
    # chown elk:elk /opt/journalbeat/data/ && \
    true

# USER elk

# Create keystore
WORKDIR /opt/journalbeat/
RUN \
    /opt/journalbeat/journalbeat -e keystore create && \
    # chown elk:elk /opt/journalbeat/data/journalbeat.keystore && \
    true

# Test configuration
RUN /opt/journalbeat/journalbeat -E name=$(cat /etc/hostname) test config -e

# No VOLUME as Journalbeat's data is (probably) transient

# Run Journalbeat via wrapper script
CMD ["/opt/journalbeat/journalbeat.sh"]
