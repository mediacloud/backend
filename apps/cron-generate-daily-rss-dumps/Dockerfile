#
# Generate daily RSS dumps Cron job
#

FROM dockermediacloud/mediacloud-cron-base:latest

# Copy Cron script
COPY bin /opt/mediacloud/bin

# Add Cron job
ADD crontab /etc/cron.d/generate_daily_rss_dumps
RUN chmod 0644 /etc/cron.d/generate_daily_rss_dumps

# Generated dumps
VOLUME /var/lib/daily_rss_dumps/

# CMD is set in "cron-base"
