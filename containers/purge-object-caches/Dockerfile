#
# Purge object caches on PostgreSQL
#

FROM mediacloud-common:latest

COPY bin/purge_object_caches.py /

# FIXME
CMD ["bash", "-c", "while true; do echo purge-object-caches...; sleep 1; done"]
