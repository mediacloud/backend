#
# Purge object caches on PostgreSQL
#

FROM mc2021/common:latest

COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["purge_object_caches.py"]
