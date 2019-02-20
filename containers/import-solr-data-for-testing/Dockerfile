#
# Import stories from PostgreSQL to Solr for testing purposes
#

FROM dockermediacloud/mediacloud-import-solr-data:latest

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# FIXME
CMD ["bash", "-c", "while true; do echo import-solr-data-for-testing...; sleep 1; done"]
