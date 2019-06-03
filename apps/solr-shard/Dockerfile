#
# Solr shard
#

FROM dockermediacloud/solr-base:latest

# Pre-fill data volume
RUN \
	mkdir -p /var/lib/solr/ && \
	#
	# Copy Solr distribution to data directory
	cp -R /opt/solr/server/* /var/lib/solr/ && \
	#
	# Copy Solr configuration to data directory
	cp -R /usr/src/solr/* /var/lib/solr/ && \
	#
	# Make sure Solr can write to data directory
	chown -R solr:solr /var/lib/solr/ && \
	#
	true

# Solr data
VOLUME /var/lib/solr/

# Solr port
EXPOSE 8983

# Run Solr shard
COPY bin/solr-shard.sh /

USER solr

CMD ["/solr-shard.sh"]
