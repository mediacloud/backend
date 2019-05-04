#
# Create missing PostgreSQL table partitions
#

FROM dockermediacloud/mediacloud-common:latest

COPY bin /opt/mediacloud/bin

CMD ["create_missing_partitions.py"]
