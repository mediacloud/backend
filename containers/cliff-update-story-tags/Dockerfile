#
# CLIFF update story tags worker
#

FROM dockermediacloud/mediacloud-cliff-base:latest

# Copy sources
COPY src/ /opt/mediacloud/src/cliff-update-story-tags/
ENV PERL5LIB="/opt/mediacloud/src/cliff-update-story-tags/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/cliff-update-story-tags/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

CMD ["cliff_update_story_tags.py"]
