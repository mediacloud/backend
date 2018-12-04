#
# Set primary media language Cron job
#

FROM dockermediacloud/mediacloud-cron-base:latest

COPY bin/set_media_primary_language.pl /

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Add Cron job
ADD crontab /etc/cron.d/set_media_primary_language
RUN chmod 0644 /etc/cron.d/set_media_primary_language
