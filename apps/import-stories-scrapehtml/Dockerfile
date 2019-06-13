#
# Import stories by scraping HTML
#

FROM dockermediacloud/import-stories-base:latest

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
COPY src/ /opt/mediacloud/src/import-stories-scrapehtml/
ENV PERL5LIB="/opt/mediacloud/src/import-stories-scrapehtml/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/import-stories-scrapehtml/python:${PYTHONPATH}"

USER mediacloud
