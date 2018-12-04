#
# Cron jobs base
#
# FIXME email the report

FROM dockermediacloud/mediacloud-common:latest

# Install Cron
RUN apt-get -y --no-install-recommends install cron

# Set "cron" as default command to run
CMD ["cron", "-f"]
