#
# Generate daily and weekly user summaries Cron job
#

FROM dockermediacloud/mediacloud-cron-base:latest

# Copy Cron script
COPY bin /opt/mediacloud/bin

# Add Cron job
ADD crontab /etc/cron.d/generate_user_summary
RUN chmod 0644 /etc/cron.d/generate_user_summary

# CMD is set in "cron-base"
