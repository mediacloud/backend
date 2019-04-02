#
# Extract story links worker
#

FROM dockermediacloud/mediacloud-topics-base:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy worker script
COPY bin/topics_extract_story_links.py /

# FIXME
CMD ["bash", "-c", "while true; do echo topics-extract-story-links...; sleep 1; done"]
