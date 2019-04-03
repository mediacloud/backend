#
# Import stories from PostgreSQL to Solr for testing purposes
#

FROM dockermediacloud/mediacloud-import-solr-data:latest

# Copy worker script
COPY bin/import_solr_data_for_testing.pm /

CMD ["/import_solr_data_for_testing.pm"]
