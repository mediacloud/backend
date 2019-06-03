#
# Export tables to run backup crawler
#

FROM dockermediacloud/cliff-base:latest

# Copy sources
COPY src/ /opt/mediacloud/src/export-tables-to-backup-crawler/
ENV PERL5LIB="/opt/mediacloud/src/export-tables-to-backup-crawler/perl:${PERL5LIB}"
ENV PYTHONPATH="/opt/mediacloud/src/export-tables-to-backup-crawler/python:${PYTHONPATH}"

# Copy exporter script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["export_tables.py"]
