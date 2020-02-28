#
# Generate retweeter scores
#

FROM dockermediacloud/topics-base:latest

# Copy sources
COPY src/ /opt/mediacloud/src/topics-generate-retweeter-scores/
ENV PERL5LIB="/opt/mediacloud/src/topics-generate-retweeter-scores/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/topics-generate-retweeter-scores/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["topics_generate_retweeter_scores_worker.pl"]
