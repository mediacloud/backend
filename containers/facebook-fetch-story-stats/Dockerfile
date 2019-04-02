#
# Fetch story stats from Facebook
#

FROM dockermediacloud/mediacloud-common:latest

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Copy worker script
COPY bin/facebook_fetch_story_stats.pm /

# FIXME
CMD ["bash", "-c", "while true; do echo facebook-fetch-story-stats...; sleep 1; done"]
