#
# NYTLabels update story tags worker
#

FROM dockermediacloud/mediacloud-nytlabels-base:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy worker script
COPY bin/nytlabels_update_story_tags.py /

# FIXME
CMD ["bash", "-c", "while true; do echo nytlabels-update-story-tags...; sleep 1; done"]
