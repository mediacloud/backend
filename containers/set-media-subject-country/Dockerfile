#
# Set media's subject country Cron job
#

FROM mediacloud-common:latest

COPY bin/set_media_subject_country.pl /

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Add Cron job
ADD crontab /etc/cron.d/set_media_subject_country
RUN chmod 0644 /etc/cron.d/set_media_subject_country

# Run Cron
CMD ["cron", "-f"]
