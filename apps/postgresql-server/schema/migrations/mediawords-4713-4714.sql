--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4713 and 4714.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4713, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4714, import this SQL file:
--
--     psql mediacloud < mediawords-4713-4714.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


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


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4714;
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
