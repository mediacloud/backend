#!/bin/sh

echo "This will delete all data in the media cloud database.  Are you sure you want to do this (y/n)?"
read REPLY

if [ $REPLY != "y" ]; then
		echo "Exiting..."
		exit 1
	fi

psql -c "DELETE FROM tags;"
psql -c "DELETE FROM tag_sets;"
pg_restore -d $PGDATABASE --no-owner --data-only -t tag_sets ../data/media_and_feed_list/tag_sets.dump
psql -c "COPY tags from STDIN "  < ../data/media_and_feed_list/media_and_feed_tags.tsv
psql -c "DELETE FROM media_tags_map;"
psql -c "DELETE FROM feeds_tags_map;"
psql -c "DELETE FROM feeds;"
psql -c "DELETE FROM media;"
pg_restore -d $PGDATABASE --data-only --no-owner -t media ../data/media_and_feed_list/media_feeds_tags.dump
pg_restore -d $PGDATABASE --data-only --no-owner -t media_tags_map ../data/media_and_feed_list/media_feeds_tags.dump
pg_restore -d $PGDATABASE --data-only --no-owner -t feeds ../data/media_and_feed_list/media_feeds_tags.dump
pg_restore -d $PGDATABASE --data-only --no-owner -t feeds_tags_map ../data/media_and_feed_list/media_feeds_tags.dump

#Update the sequence ids.  This is necessary because we are hard coding ids in the restore operations above.
#   If we don't do this, we will get strange unique constraint violation errors on the primary keys when we insert new rows.

psql -c "select setval(pg_get_serial_sequence('tag_sets', 'tag_sets_id'), (select max(tag_sets_id)+1 from tag_sets));"

psql -c "select setval(pg_get_serial_sequence('tags', 'tags_id'), (select max(tags_id)+1 from tags));"
psql -c "select setval(pg_get_serial_sequence('media', 'media_id'), (select max(media_id)+1 from media));"
psql -c "select setval(pg_get_serial_sequence('media_tags_map', 'media_tags_map_id'), (select max(media_tags_map_id)+1 from media_tags_map));"
psql -c "select setval(pg_get_serial_sequence('feeds', 'feeds_id'), (select max(feeds_id)+1 from feeds));"
psql -c "select setval(pg_get_serial_sequence('feeds_tags_map', 'feeds_tags_map_id'), (select max(feeds_tags_map_id)+1 from feeds_tags_map));"
