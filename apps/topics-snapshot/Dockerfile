#
# Topic snapshot worker
#

FROM dockermediacloud/topics-base:latest

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
COPY src/ /opt/mediacloud/src/topics-snapshot/
ENV PERL5LIB="/opt/mediacloud/src/topics-snapshot/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/topics-snapshot/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

CMD ["topics_snapshot_worker.pl"]
