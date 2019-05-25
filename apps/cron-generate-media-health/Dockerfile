#
# Generate media health Cron job
#

FROM dockermediacloud/mediacloud-cron-base:latest

# Copy sources
COPY src/ /opt/mediacloud/src/cron-generate-media-health/
ENV PERL5LIB="/opt/mediacloud/src/cron-generate-media-health/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/cron-generate-media-health/python:${PYTHONPATH}"

# Copy Cron script
COPY bin /opt/mediacloud/bin

# Add Cron job
ADD crontab /etc/cron.d/generate_media_health
RUN chmod 0644 /etc/cron.d/generate_media_health

# CMD is set in "cron-base"
