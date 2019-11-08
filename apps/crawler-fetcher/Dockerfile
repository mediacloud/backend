#
# Crawler fetcher
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
COPY src/ /opt/mediacloud/src/crawler-fetcher/
ENV PERL5LIB="/opt/mediacloud/src/crawler-fetcher/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/crawler-fetcher/python:${PYTHONPATH}"

COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["crawler-fetcher.pl"]
