#
# Generate media health Cron job
#

FROM dockermediacloud/mediacloud-cron-base:latest

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Copy Cron script
COPY bin/cron_generate_media_health.pl /

# Add Cron job
ADD crontab /etc/cron.d/generate_media_health
RUN chmod 0644 /etc/cron.d/generate_media_health

# CMD is set in "cron-base"
