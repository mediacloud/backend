#
# NYTLabels base image
#

FROM gcr.io/mcback/common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/nytlabels-base/
ENV PERL5LIB="/opt/mediacloud/src/nytlabels-base/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/nytlabels-base/python:${PYTHONPATH}"
