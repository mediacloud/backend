#
# NYTLabels update story tags worker
#

FROM dockermediacloud/mediacloud-nytlabels-base:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy worker script
COPY bin/nytlabels_update_story_tags.py /

CMD ["/nytlabels_update_story_tags.py"]
