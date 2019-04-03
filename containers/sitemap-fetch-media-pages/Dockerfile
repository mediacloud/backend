#
# Fetch sitemap pages worker
#

FROM dockermediacloud/mediacloud-common:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy worker script
COPY bin/sitemap_fetch_media_pages.py /

CMD ["/sitemap_fetch_media_pages.py"]
