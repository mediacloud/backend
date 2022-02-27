#
# Identify duplicate feeds or media sources and merge them into one entry, updating
# the feed and media source references to point to the new entry.
#

FROM gcr.io/mcback/common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/merge-media-sources/
ENV PERL5LIB="/opt/mediacloud/src/merge-media-sources/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/merge-media-sources/python:${PYTHONPATH}"

# Copy worker scripts
COPY bin /opt/mediacloud/bin

USER mediacloud

# Set a failing CMD because we'll be using the same image to run feeds merge + media merge,
# so the user is expected to set "command" in docker-compose.yml to run a specific worker.

CMD ["SET_CONTAINER_COMMAND_TO_ONE_OF_THE_WORKERS"]
