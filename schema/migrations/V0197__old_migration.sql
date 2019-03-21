


-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW feeds_stories_map
    ALTER COLUMN feeds_stories_map_id
    SET DEFAULT nextval(pg_get_serial_sequence('feeds_stories_map_partitioned', 'feeds_stories_map_partitioned_id'));

-- Prevent the next INSERT from failing
SELECT nextval(pg_get_serial_sequence('feeds_stories_map_partitioned', 'feeds_stories_map_partitioned_id'));


-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW story_sentences
    ALTER COLUMN story_sentences_id
    SET DEFAULT nextval(pg_get_serial_sequence('story_sentences_partitioned', 'story_sentences_partitioned_id'));

-- Prevent the next INSERT from failing
SELECT nextval(pg_get_serial_sequence('story_sentences_partitioned', 'story_sentences_partitioned_id'));


