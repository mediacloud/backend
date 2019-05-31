#
# Set media's subject country Cron job
#

FROM dockermediacloud/cron-base:latest

# Copy sources
COPY src/ /opt/mediacloud/src/cron-set-media-subject-country/
ENV PERL5LIB="/opt/mediacloud/src/cron-set-media-subject-country/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/cron-set-media-subject-country/python:${PYTHONPATH}"

# Copy Cron script
COPY bin /opt/mediacloud/bin

# Add Cron job
ADD crontab /etc/cron.d/set_media_subject_country
RUN chmod 0644 /etc/cron.d/set_media_subject_country

# CMD is set in "cron-base"
