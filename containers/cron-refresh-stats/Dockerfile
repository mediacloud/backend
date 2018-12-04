#
# Refresh stats Cron job
#

FROM dockermediacloud/mediacloud-cron-base:latest

COPY bin/refresh_stats.pl /

# Add Cron job
ADD crontab /etc/cron.d/refresh_stats
RUN chmod 0644 /etc/cron.d/refresh_stats
