#
# Fetch Twitter URLs
#

FROM dockermediacloud/topics-base:latest

# Install Python dependencies
COPY src/requirements.txt /var/tmp/
RUN \
    cd /var/tmp/ && \
    pip3 install -r requirements.txt && \
    rm requirements.txt && \
    rm -rf /root/.cache/ && \
    true

# Copy sources
COPY src/ /opt/mediacloud/src/topics-fetch-twitter-urls/
ENV PERL5LIB="/opt/mediacloud/src/topics-fetch-twitter-urls/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/topics-fetch-twitter-urls/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

CMD ["topics_fetch_twitter_urls_worker.py"]
