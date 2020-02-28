#
# Import stories from PostgreSQL to Solr for testing purposes
#

FROM dockermediacloud/import-solr-data:latest

USER root

# Copy sources
COPY src/ /opt/mediacloud/src/import-solr-data-for-testing/
ENV PERL5LIB="/opt/mediacloud/src/import-solr-data-for-testing/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/import-solr-data-for-testing/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["import_solr_data_for_testing_worker.pl"]
