#
# Generate daily RSS dumps Cron job
#

FROM mediacloud-common:latest

# Add Cron job
ADD crontab /etc/cron.d/generate_daily_rss_dumps
RUN chmod 0644 /etc/cron.d/generate_daily_rss_dumps

# Generated dumps
VOLUME /var/lib/daily_rss_dumps/

# Run Cron
CMD ["cron", "-f"]
