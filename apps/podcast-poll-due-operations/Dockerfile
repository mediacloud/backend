#
# Poll database for operations which should be done by now, add transcription fetch for due operations
#

FROM dockermediacloud/common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/podcast-poll-due-operations/
ENV PERL5LIB="/opt/mediacloud/src/podcast-poll-due-operations/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/podcast-poll-due-operations/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["podcast_poll_due_operations_worker.py"]
