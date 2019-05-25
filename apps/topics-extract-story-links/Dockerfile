#
# Extract story links worker
#

FROM dockermediacloud/mediacloud-topics-base:latest

# Copy sources
COPY src/ /opt/mediacloud/src/topics-extract-story-links/
ENV PERL5LIB="/opt/mediacloud/src/topics-extract-story-links/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/topics-extract-story-links/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

CMD ["topics_extract_story_links_worker.py"]
