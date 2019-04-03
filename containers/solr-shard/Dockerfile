#
# Solr shard
#

FROM dockermediacloud/mediacloud-solr-base:latest

# Solr data
VOLUME /var/lib/solr/

# Solr port
EXPOSE 8983

# Run Solr shard
COPY bin/solr-shard.sh /

CMD ["bash", "-c", "/solr-shard.sh $MC_SOLR_SHARD_COUNT"]
