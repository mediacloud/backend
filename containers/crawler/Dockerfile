#
# Crawler
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
        --verbose \
        --installdeps \
        . && \
    rm cpanfile && \
    rm -rf /root/.cpanm/ && \
    true

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Install Perl dependencies
COPY src/cpanfile /var/tmp/
RUN \
    cd /var/tmp/ && \
    cpanm \
        --mirror "$MEDIACLOUD_PERL_CPAN_MIRROR" \
        --mirror-only \
        --notest \
        --verbose \
        --installdeps \
        . && \
    rm cpanfile && \
    rm -rf /root/.cpanm/ && \
    true

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy crawler script
# (ENTRYPOINT because script expects number of threads as its parameter)
COPY bin/crawl.pl /

# FIXME
#ENTRYPOINT ["/crawl.pl"]
CMD ["bash", "-c", "while true; do echo crawler...; sleep 1; done"]
