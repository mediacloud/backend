#
# Fetch sitemap pages worker
#

FROM dockermediacloud/mediacloud-common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/sitemap-fetch-media-pages/
ENV PERL5LIB="/opt/mediacloud/src/sitemap-fetch-media-pages/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/sitemap-fetch-media-pages/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

CMD ["sitemap_fetch_media_pages.py"]
