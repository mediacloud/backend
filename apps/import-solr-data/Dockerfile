#
# Import stories from PostgreSQL to Solr
#

FROM dockermediacloud/common:latest

# Install Perl dependencies
COPY src/cpanfile /var/tmp/
RUN \
    cd /var/tmp/ && \
    cpanm \
        --mirror "$MC_PERL_CPAN_MIRROR" \
        --mirror-only \
        --notest \
        --installdeps \
        . && \
    rm cpanfile && \
    rm -rf /root/.cpanm/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/import-solr-data/
ENV PERL5LIB="/opt/mediacloud/src/import-solr-data/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/import-solr-data/python:${PYTHONPATH}"

# Copy importer script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["import_solr_data.pl", "--daemon"]
