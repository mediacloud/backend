#
# Scrape Feedly for new stories 
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
COPY src/ /opt/mediacloud/src/scrape-feedly/
ENV PERL5LIB="/opt/mediacloud/src/scrape-feedly/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/scrape-feedly/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

CMD ["scrape_feedly.pl", "--all"]
