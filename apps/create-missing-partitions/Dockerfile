#
# Create missing PostgreSQL table partitions
#

FROM mc2021/common:latest

COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["create_missing_partitions.py"]
