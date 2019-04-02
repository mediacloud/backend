#
# Fetch Twitter URLs
#

FROM dockermediacloud/mediacloud-topics-base:latest

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy worker script
COPY bin/topics_fetch_twitter_urls.py /

# FIXME
CMD ["bash", "-c", "while true; do echo topics-fetch-twitter-urls...; sleep 1; done"]
