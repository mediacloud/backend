#
# Fetch story stats from Facebook
#

FROM dockermediacloud/mediacloud-common:latest

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Copy worker script
COPY bin/facebook_fetch_story_stats.pm /

CMD ["/facebook_fetch_story_stats.pm"]
