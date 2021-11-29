#
# Gradually move rows from unsharded tables to the sharded ones
#

FROM gcr.io/mcback/common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/move-rows-to-shards/
ENV PERL5LIB="/opt/mediacloud/src/move-rows-to-shards/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/move-rows-to-shards/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["workflow_worker.py"]
