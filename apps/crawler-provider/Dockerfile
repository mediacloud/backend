#
# Crawler provider
#

FROM dockermediacloud/mediacloud-common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/crawler-provider/
ENV PERL5LIB="/opt/mediacloud/src/crawler-provider/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/crawler-provider/python:${PYTHONPATH}"

COPY bin /opt/mediacloud/bin

CMD ["crawler-provider.py"]
