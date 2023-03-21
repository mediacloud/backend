#
# Solr base
#

FROM gcr.io/mcback/java-base:latest

# Solr version
ENV MEDIACLOUD_SOLR_VERSION="6.5.0"

# Download and extract Solr
# (distribution needed for running both Solr itself and ZooKeeper)
RUN \
    mkdir -p /opt/solr/ && \
    /dl_to_stdout.sh "https://mediacloud-archive-apache-org.s3.amazonaws.com/solr-${MEDIACLOUD_SOLR_VERSION}.tgz" | \
	    tar -zx -C /opt/solr/ --strip 1 && \
	true

# Copy Solr configuration
RUN mkdir -p /usr/src/
COPY src/solr/ /usr/src/solr/

# Try to create 64-bit enabled mediacloud64 collection by cloning config
# NOTE: collections/mediacloud/conf/solrconfig.xml uses
#	${mediacloud.luceneMatchVersion} ${mediacloud.solr_webapp_dir} ${mediacloud.solr_dist_dir}
#	which reference JVM properties set in solr-shard/bin/solr-shard.sh
# ALSO: core.properties has "instanceDir=/var/lib/solr/mediacloud" (dir does not exist?!)
#	will be wacked to .../mediacloud64 (also does not exist)
RUN \
    mkdir -p /usr/src/solr/collections/mediacloud64 && \
    cp -rp /usr/src/solr/collections/mediacloud/* /usr/src/solr/collections/mediacloud64/ && \
    sed -i.32 's/mediacloud/mediacloud64/' /usr/src/solr/collections/mediacloud64/core.properties && \
    sed -i.32 '/<field name=.*type="int"/s/"int"/"long"/' /usr/src/solr/collections/mediacloud64/conf/schema.xml && \
    true

# Add user that Solr will run as
RUN useradd -ms /bin/bash solr
