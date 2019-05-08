#
# Migrate (install or update) database schema and exit
#

FROM dockermediacloud/mediacloud-common:latest

# Copy sources
COPY src/ /opt/mediacloud/src/migrate-schema/
ENV PERL5LIB="/opt/mediacloud/src/migrate-schema/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/migrate-schema/python:${PYTHONPATH}"

# Copy schema upgrade script
COPY bin /opt/mediacloud/bin

# Copy full schema and migrations
COPY schema/ /opt/mediacloud/schema/

# Just idle around because tests get run with --abort-on-container-exit
CMD ["migrate-schema.py", "--sleep_after_finishing"]
