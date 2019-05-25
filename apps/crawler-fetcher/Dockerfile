#
# Crawler fetcher
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
COPY src/ /opt/mediacloud/src/crawler-fetcher/
ENV PERL5LIB="/opt/mediacloud/src/crawler-fetcher/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/crawler-fetcher/python:${PYTHONPATH}"

COPY bin /opt/mediacloud/bin

CMD ["crawler-fetcher.pl"]
