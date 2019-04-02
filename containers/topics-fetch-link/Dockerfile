#
# Fetch topic link worker
#

FROM dockermediacloud/mediacloud-topics-base:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# FIXME
CMD ["bash", "-c", "while true; do echo topics-fetch-link...; sleep 1; done"]
