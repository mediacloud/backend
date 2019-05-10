#
# (Re)scrape media worker
#

FROM dockermediacloud/mediacloud-common:latest

# Install Perl dependencies
COPY src/cpanfile /var/tmp/
RUN \
    cd /var/tmp/ && \
    cpanm \
        --mirror "$MEDIACLOUD_PERL_CPAN_MIRROR" \
        --mirror-only \
        --notest \
        --installdeps \
        . && \
    rm cpanfile && \
    rm -rf /root/.cpanm/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/rescrape-media/
ENV PERL5LIB="/opt/mediacloud/src/rescrape-media/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/rescrape-media/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

CMD ["rescrape_media_worker.pl"]
