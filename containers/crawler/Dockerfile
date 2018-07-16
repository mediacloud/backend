#
# Crawler
#

FROM mediacloud-common:latest

# Install dependencies
RUN \
    #
    # Required by XML::LibXML
    apt-get -y --no-install-recommends install libxml2-dev && \
    #
    true

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

# Run crawler
# (ENTRYPOINT because script expects number of threads as its parameter)
COPY bin/crawl.pl /
ENTRYPOINT ["/crawl.pl"]
