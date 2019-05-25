#
# Print long running job states
#

FROM dockermediacloud/mediacloud-cron-base:latest

# Copy Cron script
COPY bin /opt/mediacloud/bin

# Add Cron job
ADD crontab /etc/cron.d/print_long_running_job_states
RUN chmod 0644 /etc/cron.d/print_long_running_job_states

# CMD is set in "cron-base"
