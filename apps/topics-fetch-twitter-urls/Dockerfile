#
# Fetch Twitter URLs
#

FROM dockermediacloud/topics-base:latest

# Copy sources
COPY src/ /opt/mediacloud/src/topics-fetch-twitter-urls/
ENV PERL5LIB="/opt/mediacloud/src/topics-fetch-twitter-urls/perl:${PERL5LIB}" \
	PYTHONPATH="/opt/mediacloud/src/topics-fetch-twitter-urls/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["topics_fetch_twitter_urls_worker.py"]
