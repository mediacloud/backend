#
# Fetch topic link worker
#

FROM dockermediacloud/mediacloud-topics-base:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy worker script
COPY bin/topics_fetch_link.py /

CMD ["/topics_fetch_link.py"]
