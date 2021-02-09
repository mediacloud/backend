#
# Import stories from PostgreSQL to Solr
#

FROM gcr.io/mcback/common:latest

# Install Perl dependencies
COPY src/cpanfile /var/tmp/
RUN \
    cd /var/tmp/ && \
    cpm install --global --resolver 02packages --no-prebuilt --mirror "$MC_PERL_CPAN_MIRROR" && \
    rm cpanfile && \
    rm -rf /root/.perl-cpm/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/import-solr-data/
ENV PERL5LIB="/opt/mediacloud/src/import-solr-data/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/import-solr-data/python:${PYTHONPATH}"

# Copy importer script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["import_solr_data.pl", "--daemon"]
