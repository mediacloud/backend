#
# CLIFF base image
#

FROM dockermediacloud/common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/cliff-base/
ENV PERL5LIB="/opt/mediacloud/src/cliff-base/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/cliff-base/python:${PYTHONPATH}"
