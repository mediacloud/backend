#
# NYTLabels base image
#

FROM dockermediacloud/mediacloud-common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/nytlabels-base/
ENV PERL5LIB="/opt/mediacloud/src/nytlabels-base/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/nytlabels-base/python:${PYTHONPATH}"
