#!/bin/sh

pg_dump -f ../data/media_and_feed_list/media_feeds_tags.dump -F c  -t media -t feeds -t media_tags_map -t feeds_tags_map 
pg_dump -f ../data/media_and_feed_list/tag_sets.dump -F c  -t tag_sets 
psql -c "COPY (select distinct(tags.*) from tags natural join media_tags_map) to STDOUT "  > ../data/media_and_feed_list/media_tags.tsv
