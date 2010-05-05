#!/bin/sh

nohup bash -c " ( \
./regenerate_tag_tags.sh  && \
./dump_website_required_tables.sh  && \
touch /mnt/tmp/website_table_dump_complete ) " &
