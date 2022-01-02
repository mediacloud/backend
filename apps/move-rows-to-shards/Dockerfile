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

# Set a failing CMD because we'll be using the same image to run:
#
# * "workflow_worker.py" - processes workflow;
# * "activities_worker.py" - processes workflow's activities.
#
# so the user is expected to set "command" in docker-compose.yml to run a specific worker.
#
CMD ["SET_CONTAINER_COMMAND_TO_ONE_OF_THE_WORKERS"]
