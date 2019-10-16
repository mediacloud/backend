#
# Cron jobs base
#
# FIXME email the report

FROM dockermediacloud/common:latest

# Install Cron
RUN \
    apt-get -y --no-install-recommends install cron && \
    #
    # Default Cron jobs don't have to be run
    rm -f /etc/cron.d/* && \
    rm -f /etc/cron.daily/* && \
    rm -f /etc/cron.hourly/* && \
    rm -f /etc/cron.monthly/* && \
    rm -f /etc/cron.weekly/* && \
    echo -n > /etc/crontab && \
    true

# Copy wrapper script
COPY bin/cron.sh /

# Set wrapper script as default command to run
CMD ["/cron.sh"]
