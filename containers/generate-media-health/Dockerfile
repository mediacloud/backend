#
# Generate media health Cron job
#
# FIXME send out by email
#

FROM mediacloud-common:latest

# Add Cron job
ADD crontab /etc/cron.d/generate_media_health
RUN chmod 0644 /etc/cron.d/generate_media_health

# Run Cron
CMD ["cron", "-f"]
