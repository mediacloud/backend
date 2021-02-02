#
# Auditbeat for ELK auditd logging
#

FROM gcr.io/mcback/base:latest

# Install Auditbeat
# (https://www.elastic.co/downloads/beats/auditbeat)
ENV ELK_AUDITBEAT_VERSION=7.10.0
RUN \
    mkdir -p /opt/auditbeat/ && \
    curl --fail --location --retry 3 --retry-delay 5 "https://artifacts.elastic.co/downloads/beats/auditbeat/auditbeat-${ELK_AUDITBEAT_VERSION}-linux-x86_64.tar.gz" | \
        tar -zx -C /opt/auditbeat/ --strip 1 && \
    true

# Copy over configuration
COPY auditbeat.yml /opt/auditbeat/
COPY auditbeat-ilm.json /opt/auditbeat/
RUN \
    # chown elk:elk /opt/auditbeat/auditbeat.yml && \
    chmod go-w /opt/auditbeat/auditbeat.yml && \
    true

# Copy worker wrapper
COPY auditbeat.sh /opt/auditbeat/
RUN chmod +x /opt/auditbeat/auditbeat.sh

# Create data directory
RUN \
    mkdir /opt/auditbeat/data/ && \
    # chown elk:elk /opt/auditbeat/data/ && \
    true

# Create directories to mount from host
RUN \
    mkdir -p /opt/auditbeat/host/ && \
    mkdir -p /opt/auditbeat/host/bin/ && \
    mkdir -p /opt/auditbeat/host/usr/bin/ && \
    mkdir -p /opt/auditbeat/host/sbin/ && \
    mkdir -p /opt/auditbeat/host/usr/sbin/ && \
    mkdir -p /opt/auditbeat/host/etc/ && \
    mkdir -p /opt/auditbeat/host/var/log/ && \
    true

# Create keystore
WORKDIR /opt/auditbeat/
RUN \
    /opt/auditbeat/auditbeat -e keystore create && \
    # chown elk:elk /opt/auditbeat/data/auditbeat.keystore && \
    true

# Configuration test won't work as it doesn't have required auditd permissions
# at build time:
# RUN /opt/auditbeat/auditbeat -E name=$(cat /etc/hostname) test config -e

# No VOLUME as auditbeat's data is (probably) transient

# Run auditbeat via wrapper script
CMD ["/opt/auditbeat/auditbeat.sh"]
