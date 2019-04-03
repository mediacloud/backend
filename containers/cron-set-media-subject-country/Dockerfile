#
# Set media's subject country Cron job
#

FROM dockermediacloud/mediacloud-cron-base:latest

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Copy Cron script
COPY bin/cron_set_media_subject_country.pl /

# Add Cron job
ADD crontab /etc/cron.d/set_media_subject_country
RUN chmod 0644 /etc/cron.d/set_media_subject_country

# CMD is set in "cron-base"
