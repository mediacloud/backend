#
# Report rescraping changes Cron job
#
# Make sure that this job and "rescrape-due-media" are being run at more or
# less opposite times of day because one of them initializes rescraping and the
# other reports status of the last rescrape.
#
# FIXME disable initially

FROM dockermediacloud/mediacloud-cron-base:latest

# Copy worker script
COPY bin/cron_rescraping_changes.sh /

# Add Cron job
ADD crontab /etc/cron.d/rescraping_changes
RUN chmod 0644 /etc/cron.d/rescraping_changes

# CMD is set in "cron-base"
