#
# Crawler provider
#

FROM gcr.io/mcback/common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/crawler-provider/
ENV PERL5LIB="/opt/mediacloud/src/crawler-provider/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/crawler-provider/python:${PYTHONPATH}"

COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["crawler-provider.py"]
