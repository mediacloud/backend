#
# Create missing PostgreSQL table partitions
#

FROM dockermediacloud/mediacloud-common:latest

# Copy worker script
COPY bin/create_missing_partitions.py /

CMD ["/create_missing_partitions.py"]
