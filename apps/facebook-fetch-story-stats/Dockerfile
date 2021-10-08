#
# Fetch story stats from Facebook
#

FROM gcr.io/mcback/common:latest

# install package to get engagement stats from facebook posts
RUN pip3 install facebook-scraper==0.2.47

# Copy sources
COPY src/ /opt/mediacloud/src/facebook-fetch-story-stats/
ENV PERL5LIB="/opt/mediacloud/src/facebook-fetch-story-stats/perl:${PERL5LIB}" \
    PYTHONPATH="/opt/mediacloud/src/facebook-fetch-story-stats/python:${PYTHONPATH}"

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["facebook_fetch_story_stats_worker.py"]
