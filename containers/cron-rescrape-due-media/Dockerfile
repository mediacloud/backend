#
# Add due media to the rescraping queue Cron job
#
# Make sure that this job and "rescraping-changes" are being run at more or
# less opposite times of day because one of them initializes rescraping and the
# other reports status of the last rescrape.
#
# FIXME disable initially

FROM dockermediacloud/mediacloud-cron-base:latest

# Copy worker script
COPY bin/cron_rescrape_due_media.pl /

# Add Cron job
ADD crontab /etc/cron.d/rescrape_due_media
RUN chmod 0644 /etc/cron.d/rescrape_due_media

# CMD is set in "cron-base"
