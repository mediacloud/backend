#
# Generate daily and weekly user summaries Cron job
#

FROM mediacloud-cron-base:latest

# Add Cron job
ADD crontab /etc/cron.d/generate_user_summary
RUN chmod 0644 /etc/cron.d/generate_user_summary
