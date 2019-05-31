#
# CLIFF fetch annotation worker
#

FROM dockermediacloud/cliff-base:latest

# Copy sources
COPY src/ /opt/mediacloud/src/cliff-fetch-annotation/
ENV PERL5LIB="/opt/mediacloud/src/cliff-fetch-annotation/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/cliff-fetch-annotation/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

CMD ["cliff_fetch_annotation_worker.py"]
