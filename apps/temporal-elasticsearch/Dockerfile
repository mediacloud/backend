#
# Elasticsearch for Temporal
#

FROM gcr.io/mcback/elasticsearch-base:latest

USER root

COPY config/* /opt/elasticsearch/config/

# Create keystore and move it to data volume
RUN \
    #
    # Merge base and Temporal configs into one
    cat \
        /opt/elasticsearch/config/elasticsearch-base.yml \
        /opt/elasticsearch/config/temporal-elasticsearch.yml \
        > /opt/elasticsearch/config/elasticsearch.yml && \
    #
    true

USER elasticsearch

# Preload with Temporal index template
# (https://github.com/temporalio/temporal/blob/v1.7.0/schema/elasticsearch/v7/visibility/index_template.json)
COPY index_template.json setup_index_template.sh /
RUN /setup_index_template.sh
USER root
RUN rm /index_template.json /setup_index_template.sh
USER elasticsearch

CMD ["/opt/elasticsearch/bin/elasticsearch.sh"]
