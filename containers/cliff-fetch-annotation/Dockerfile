#
# CLIFF fetch annotation worker
#

FROM dockermediacloud/mediacloud-cliff-base:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy worker script
COPY bin/cliff_fetch_annotation.py /

CMD ["/cliff_fetch_annotation.py"]
