#
# NYTLabels fetch annotation worker
#

FROM dockermediacloud/mediacloud-nytlabels-base:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy worker script
COPY bin/nytlabels_fetch_annotation.py /

CMD ["/nytlabels_fetch_annotation.py"]
