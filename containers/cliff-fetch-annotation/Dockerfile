#
# CLIFF fetch annotation worker
#

FROM dockermediacloud/mediacloud-cliff-base:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy worker script
COPY bin/cliff_fetch_annotation.py /

# FIXME
CMD ["bash", "-c", "while true; do echo cliff-fetch-annotation...; sleep 1; done"]
