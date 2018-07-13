#
# Generate daily and weekly user summaries Cron job
#
# FIXME email the report

FROM mediacloud-common:latest

# Add Cron job
ADD crontab /etc/cron.d/generate_daily_user_summary
RUN chmod 0644 /etc/cron.d/rescrape_due_media

# Run Cron
CMD ["cron", "-f"]
