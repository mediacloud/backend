#
# Upgrade database schema and exit
#

FROM dockermediacloud/mediacloud-common:latest

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Copy Python sources
COPY src/python/ /usr/lib/python3/dist-packages/

# Copy schema upgrade script
COPY bin/upgrade_database_schema.pl /

CMD ["/upgrade_database_schema.pl"]
