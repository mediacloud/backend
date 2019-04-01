#
# NYTLabels fetch annotation worker
#

FROM dockermediacloud/mediacloud-nytlabels-base:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy worker script
COPY bin/nytlabels_fetch_annotation.py /

# FIXME
CMD ["bash", "-c", "while true; do echo nytlabels-fetch-annotation...; sleep 1; done"]
