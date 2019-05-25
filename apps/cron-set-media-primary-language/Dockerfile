#
# Set primary media language Cron job
#

FROM dockermediacloud/mediacloud-cron-base:latest

# Copy sources
COPY src/ /opt/mediacloud/src/cron-set-media-primary-language/
ENV PERL5LIB="/opt/mediacloud/src/cron-set-media-primary-language/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/cron-set-media-primary-language/python:${PYTHONPATH}"

# Copy Cron script
COPY bin /opt/mediacloud/bin

# Add Cron job
ADD crontab /etc/cron.d/set_media_primary_language
RUN chmod 0644 /etc/cron.d/set_media_primary_language

# CMD is set in "cron-base"
