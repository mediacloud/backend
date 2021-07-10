#
# Extract story links worker
#

FROM mc2021/topics-base:latest

# Copy sources
COPY src/ /opt/mediacloud/src/topics-extract-story-links/
ENV PERL5LIB="/opt/mediacloud/src/topics-extract-story-links/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/topics-extract-story-links/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["topics_extract_story_links_worker.py"]
