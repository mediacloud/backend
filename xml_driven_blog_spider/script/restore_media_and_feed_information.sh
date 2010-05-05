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
