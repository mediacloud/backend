#
# Import stories from PostgreSQL to Solr
#

FROM dockermediacloud/common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/import-solr-data/
ENV PERL5LIB="/opt/mediacloud/src/import-solr-data/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/import-solr-data/python:${PYTHONPATH}"

# Copy importer script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["import_solr_data.pl", "--daemon"]
