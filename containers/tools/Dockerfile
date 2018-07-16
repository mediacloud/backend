#
# Various one-off tools
#

FROM mediacloud-common:latest

# Install dependencies
RUN \
    #
    # Required by Perl::Tidy
    apt-get -y --no-install-recommends install libtidy-dev && \
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

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Copy tools
COPY bin/ /

# Run the tool
# (ENTRYPOINT because the tool's path is to follow)
ENTRYPOINT ["bash", "-c"]
