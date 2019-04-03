#
# CLIFF update story tags worker
#

FROM dockermediacloud/mediacloud-cliff-base:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy worker script
COPY bin/cliff_update_story_tags.py /

CMD ["/cliff_update_story_tags.py"]
