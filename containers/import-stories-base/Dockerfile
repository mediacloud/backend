#
# Base image for code that imports stories from arbitrary sources
#

FROM dockermediacloud/mediacloud-extract-and-vector:latest

# Copy sources
COPY src/ /opt/mediacloud/src/import-stories-base/
ENV PERL5LIB="/opt/mediacloud/src/import-stories-base/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/import-stories-base/python:${PYTHONPATH}"

# Copy importer script
COPY bin /opt/mediacloud/bin
