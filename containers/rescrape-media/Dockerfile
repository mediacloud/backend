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
        --verbose \
        --installdeps \
        . && \
    rm cpanfile && \
    rm -rf /root/.cpanm/ && \
    true

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Copy worker script
COPY bin/rescrape_media.pm /

CMD ["/rescrape_media.pm"]
