#
# (Re)scrape media worker
#

FROM dockermediacloud/common:latest

# Install Perl dependencies
COPY src/cpanfile /var/tmp/
RUN \
    cd /var/tmp/ && \
    cpm install --global --resolver 02packages --no-prebuilt --mirror "$MC_PERL_CPAN_MIRROR" && \
    rm cpanfile && \
    rm -rf /root/.perl-cpm/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/rescrape-media/
ENV PERL5LIB="/opt/mediacloud/src/rescrape-media/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/rescrape-media/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["rescrape_media_worker.pl"]
