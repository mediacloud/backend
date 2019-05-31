#
# Refresh stats Cron job
#

FROM dockermediacloud/cron-base:latest

# Copy Cron script
COPY bin /opt/mediacloud/bin

# Add Cron job
ADD crontab /etc/cron.d/refresh_stats
RUN chmod 0644 /etc/cron.d/refresh_stats

# CMD is set in "cron-base"
