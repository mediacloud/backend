#
# Import stories by fetching them from Feedly
#

FROM dockermediacloud/import-stories-base:latest

# Install Perl dependencies
COPY src/cpanfile /var/tmp/
RUN \
    cd /var/tmp/ && \
    cpm install --global --resolver 02packages --no-prebuilt --mirror "$MC_PERL_CPAN_MIRROR" && \
    rm cpanfile && \
    rm -rf /root/.perl-cpm/ && \
    true

# Create directory for cache
RUN \
    mkdir -p /var/cache/feedly_feed_stories/ && \
    chown -R mediacloud:mediacloud /var/cache/feedly_feed_stories/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/import-stories-feedly/
ENV PERL5LIB="/opt/mediacloud/src/import-stories-feedly/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/import-stories-feedly/python:${PYTHONPATH}"

# Copy scraper script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["scrape_feedly.pl", "--all"]
