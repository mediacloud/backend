#
# Create missing PostgreSQL table partitions
#

FROM gcr.io/mcback/common:latest

COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["create_missing_partitions.py"]
