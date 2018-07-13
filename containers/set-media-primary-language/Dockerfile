#
# Set primary media language Cron job
#

FROM mediacloud-common:latest

# Add Cron job
ADD crontab /etc/cron.d/set_media_primary_language
RUN chmod 0644 /etc/cron.d/set_media_primary_language

# Run Cron
CMD ["cron", "-f"]
