#
# Topic snapshot worker
#

FROM mediacloud-topics-base:latest

# Install dependencies
RUN \
    #
    # GEXF generation
    apt-get -y --no-install-recommends install graphviz && \
    apt-get -y --no-install-recommends install graphviz-dev && \
    apt-get -y --no-install-recommends install libgraphviz-dev && \
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

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# FIXME
CMD ["bash", "-c", "while true; do echo topics-snapshot...; sleep 1; done"]
