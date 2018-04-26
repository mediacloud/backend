#
# Solr shard
#

FROM mediacloud-solr-base:latest

# Solr data
VOLUME /var/lib/solr/

# Solr port
EXPOSE 8983

# Run Solr shard
# (ENTRYPOINT because script expects number of shards as its parameter)
COPY bin/solr-shard.sh /
ENTRYPOINT ["/solr-shard.sh"]
