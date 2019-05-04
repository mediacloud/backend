#
# Fetch topic link worker
#

FROM dockermediacloud/mediacloud-topics-base:latest

# Copy sources
COPY src/ /opt/mediacloud/src/topics-fetch-link/
ENV PERL5LIB="/opt/mediacloud/src/topics-fetch-link/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/topics-fetch-link/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

CMD ["topics_fetch_link.py"]
