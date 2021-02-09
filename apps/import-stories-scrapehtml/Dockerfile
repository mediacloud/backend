#
# Import stories by scraping HTML
#

FROM gcr.io/mcback/import-stories-base:latest

# Install Perl dependencies
COPY src/cpanfile /var/tmp/
RUN \
    cd /var/tmp/ && \
    cpm install --global --resolver 02packages --no-prebuilt --mirror "$MC_PERL_CPAN_MIRROR" && \
    rm cpanfile && \
    rm -rf /root/.perl-cpm/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/import-stories-scrapehtml/
ENV PERL5LIB="/opt/mediacloud/src/import-stories-scrapehtml/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/import-stories-scrapehtml/python:${PYTHONPATH}"

USER mediacloud
