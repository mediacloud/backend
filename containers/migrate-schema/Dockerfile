#
# Migrate (install or update) database schema and exit
#

FROM dockermediacloud/mediacloud-common:latest

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy schema upgrade script
COPY bin/migrate_schema.py /

# Copy full schema and migrations
COPY schema/ /

CMD ["/migrate_schema.py"]
