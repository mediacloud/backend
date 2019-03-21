


DROP FUNCTION downloads_p_success_content_create_partitions();
DROP FUNCTION downloads_p_success_feed_create_partitions();
DROP FUNCTION create_missing_partitions();


CREATE OR REPLACE FUNCTION downloads_success_content_create_partitions()
RETURNS VOID AS
$$

    SELECT downloads_create_subpartitions('downloads_success_content');

$$
LANGUAGE SQL;


CREATE OR REPLACE FUNCTION downloads_success_feed_create_partitions()
RETURNS VOID AS
$$

    SELECT downloads_create_subpartitions('downloads_success_feed');

$$
LANGUAGE SQL;


CREATE OR REPLACE FUNCTION create_missing_partitions()
RETURNS VOID AS
$$
BEGIN

    RAISE NOTICE 'Creating partitions in "downloads_success_content" table...';
    PERFORM downloads_success_content_create_partitions();

    RAISE NOTICE 'Creating partitions in "downloads_success_feed" table...';
    PERFORM downloads_success_feed_create_partitions();

    RAISE NOTICE 'Creating partitions in "download_texts_p" table...';
    PERFORM download_texts_p_create_partitions();

    RAISE NOTICE 'Creating partitions in "stories_tags_map_p" table...';
    PERFORM stories_tags_map_create_partitions();

    RAISE NOTICE 'Creating partitions in "story_sentences_p" table...';
    PERFORM story_sentences_create_partitions();

    RAISE NOTICE 'Creating partitions in "feeds_stories_map_p" table...';
    PERFORM feeds_stories_map_create_partitions();

END;
$$
LANGUAGE plpgsql;




