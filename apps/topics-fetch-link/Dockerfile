#
# Fetch topic link worker
#

FROM dockermediacloud/topics-base:latest

# Copy sources
COPY src/ /opt/mediacloud/src/topics-fetch-link/
ENV PERL5LIB="/opt/mediacloud/src/topics-fetch-link/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/topics-fetch-link/python:${PYTHONPATH}"
ENV MC_LOGGING_LEVEL=DEBUG

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["topics_fetch_link_worker.py"]
