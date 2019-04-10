#
# Migrate (install or update) database schema and exit
#

FROM dockermediacloud/mediacloud-common:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy schema upgrade script
COPY bin/migrate_schema.py /

# Copy full schema and migrations
COPY schema/ /schema/

# Just idle around because tests get run with --abort-on-container-exit
CMD ["/migrate_schema.py", "--sleep_after_finishing"]
