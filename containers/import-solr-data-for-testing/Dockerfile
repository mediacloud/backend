#
# Import stories from PostgreSQL to Solr for testing purposes
#

FROM dockermediacloud/mediacloud-import-solr-data:latest

# Copy worker script
COPY bin /opt/mediacloud/bin

CMD ["import_solr_data_for_testing.pm"]
