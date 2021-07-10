#
# Elasticsearch for ELK logging stack
#

FROM mc2021/elasticsearch-base:latest

USER root

# Install Elasticsearch Amazon S3 plugin for ILS archival
# (we use curl to be able to configure retries and such)
RUN \
    curl --fail --location --retry 3 --retry-delay 5 "https://artifacts.elastic.co/downloads/elasticsearch-plugins/repository-s3/repository-s3-${MC_ELASTICSEARCH_VERSION}.zip" > \
        /var/tmp/es-s3-plugin.zip && \
    /opt/elasticsearch/bin/elasticsearch-plugin install --batch file:///var/tmp/es-s3-plugin.zip && \
    rm /var/tmp/es-s3-plugin.zip && \
    true

COPY config/* /opt/elasticsearch/config/
COPY bin/* /opt/elasticsearch/bin/

# Create keystore and move it to data volume
RUN \
    #
    # Merge base and ELK configs into one
    cat \
        /opt/elasticsearch/config/elasticsearch-base.yml \
        /opt/elasticsearch/config/elk-elasticsearch.yml \
        > /opt/elasticsearch/config/elasticsearch.yml && \
    #
    true

USER elasticsearch

# Elasticsearch data
VOLUME /var/lib/elasticsearch

CMD ["/opt/elasticsearch/bin/elk-elasticsearch.sh"]
