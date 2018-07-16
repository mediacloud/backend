#
# NYTLabels update story tags worker
#

FROM mediacloud-nytlabels-base:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# FIXME
CMD ["bash", "-c", "while true; do echo nytlabels-update-story-tags...; sleep 1; done"]
