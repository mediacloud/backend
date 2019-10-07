#
# Fetch story stats from Facebook
#

FROM dockermediacloud/common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/facebook-fetch-story-stats/
ENV PERL5LIB="/opt/mediacloud/src/facebook-fetch-story-stats/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/facebook-fetch-story-stats/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["facebook_fetch_story_stats_worker.pl"]
