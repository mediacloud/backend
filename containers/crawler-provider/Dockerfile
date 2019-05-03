#
# Crawler provider
#

FROM dockermediacloud/mediacloud-common:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

COPY bin/crawler-provider.py /

CMD ["/crawler-provider.py"]
