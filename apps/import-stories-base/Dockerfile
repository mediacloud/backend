#
# Base image for code that imports stories from arbitrary sources
#

FROM gcr.io/mcback/extract-and-vector:latest

USER root

# Install Perl dependencies
COPY src/cpanfile /var/tmp/
RUN \
    cd /var/tmp/ && \
    cpm install --global --resolver 02packages --no-prebuilt --mirror "$MC_PERL_CPAN_MIRROR" && \
    rm cpanfile && \
    rm -rf /root/.perl-cpm/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/import-stories-base/
ENV PERL5LIB="/opt/mediacloud/src/import-stories-base/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/import-stories-base/python:${PYTHONPATH}"

# Copy importer script
COPY bin /opt/mediacloud/bin

