#
# Purge object caches on PostgreSQL
#

FROM dockermediacloud/common:latest

COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["purge_object_caches.py"]
