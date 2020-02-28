#
# Solr base
#

FROM dockermediacloud/java-base:latest

# Solr version
ENV MEDIACLOUD_SOLR_VERSION="6.5.0"

# Download and extract Solr
# (distribution needed for running both Solr itself and ZooKeeper)
RUN \
    mkdir -p /opt/solr/ && \
    curl --fail --location --retry 3 --retry-delay 5 "https://archive.apache.org/dist/lucene/solr/${MEDIACLOUD_SOLR_VERSION}/solr-${MEDIACLOUD_SOLR_VERSION}.tgz" | \
	    tar -zx -C /opt/solr/ --strip 1 && \
	true

# Copy Solr configuration
RUN mkdir -p /usr/src/
COPY src/solr/ /usr/src/solr/

# Add user that Solr will run as
RUN useradd -ms /bin/bash solr
