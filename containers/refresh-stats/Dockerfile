#
# Refresh stats Cron job
#

FROM mediacloud-common:latest

# Add Cron job
ADD crontab /etc/cron.d/refresh_stats
RUN chmod 0644 /etc/cron.d/refresh_stats

# Run Cron
CMD ["cron", "-f"]
