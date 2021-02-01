#
# Fetch sitemap pages worker
#

FROM gcr.io/mcback/common:latest

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/sitemap-fetch-media-pages/
ENV PERL5LIB="/opt/mediacloud/src/sitemap-fetch-media-pages/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/sitemap-fetch-media-pages/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["sitemap_fetch_media_pages_worker.py"]
