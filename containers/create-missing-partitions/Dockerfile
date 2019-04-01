#
# Create missing PostgreSQL table partitions
#

FROM dockermediacloud/mediacloud-common:latest

# Copy worker script
COPY bin/create_missing_partitions.py /

# FIXME
CMD ["bash", "-c", "while true; do echo create-missing-partitions...; sleep 1; done"]
