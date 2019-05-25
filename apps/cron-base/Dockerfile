#
# Cron jobs base
#
# FIXME email the report

FROM dockermediacloud/mediacloud-common:latest

# Install Cron
RUN \
    apt-get -y --no-install-recommends install cron && \
    #
    # Default Cron jobs don't have to be run
    rm -f /etc/cron.d/* && \
    true

# Set "cron" as default command to run
CMD ["cron", "-f"]
