#
# Gradually move rows from "stories_unpartitioned" to "stories_partitioned"
#

FROM gcr.io/mcback/common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/partition-stories-move-rows/
ENV PERL5LIB="/opt/mediacloud/src/partition-stories-move-rows/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/partition-stories-move-rows/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["workflow_worker.py"]
