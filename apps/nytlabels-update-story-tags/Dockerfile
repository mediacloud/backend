#
# NYTLabels update story tags worker
#

FROM gcr.io/mcback/nytlabels-base:latest

# Copy sources
COPY src/ /opt/mediacloud/src/nytlabels-update-story-tags/
ENV PERL5LIB="/opt/mediacloud/src/nytlabels-update-story-tags/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/nytlabels-update-story-tags/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["nytlabels_update_story_tags_worker.py"]
