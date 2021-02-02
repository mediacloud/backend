#
# Import stories from PostgreSQL to Solr for testing purposes
#

FROM gcr.io/mcback/import-solr-data:latest

USER root

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["import_solr_data_for_testing_worker.pl"]
