#
# Set primary media language Cron job
#

FROM dockermediacloud/mediacloud-cron-base:latest

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Copy Cron script
COPY bin/cron_set_media_primary_language.pl /

# Add Cron job
ADD crontab /etc/cron.d/set_media_primary_language
RUN chmod 0644 /etc/cron.d/set_media_primary_language
