#!/bin/sh
time nice pg_dump  --clean --no-owner -t  media  -t  media_google_charts_map_url -t  media_tag_tag_counts -t  media_tags_map -t media_tag_counts -t tag_sets -t  tags -t  top_ten_tags_for_media  -t tag_lookup --file=/mnt/tmp/website_table_`date | tr ' ' '_'| tr ':' '_' `.sql > /mnt/tmp/website_table_`date | tr ' ' '_'| tr ':' '_' `.log

