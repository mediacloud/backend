--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4719 and 4720.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4719, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4720, import this SQL file:
--
--     psql mediacloud < mediawords-4719-4720.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--


DROP TRIGGER downloads_error_cascade_ref_downloads_trigger
    ON downloads_error;

DROP TRIGGER downloads_feed_error_cascade_ref_downloads_trigger
    ON downloads_feed_error;

DROP TRIGGER downloads_fetching_cascade_ref_downloads_trigger
    ON downloads_fetching;

DROP TRIGGER downloads_pending_cascade_ref_downloads_trigger
    ON downloads_pending;


DO $$
DECLARE
    tables CURSOR FOR
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public' AND (
            tablename LIKE 'downloads_success_content_%' OR
            tablename LIKE 'downloads_success_feed_%'
        )
        ORDER BY tablename;
BEGIN
    FOR table_record IN tables LOOP

        EXECUTE '
            DROP TRIGGER ' || table_record.tablename || '_cascade_ref_downloads_trigger
                ON ' || table_record.tablename || ';';

    END LOOP;
END
$$;


DROP FUNCTION cascade_ref_downloads_trigger();


--
-- 2 of 2. Reset the database version.
--
CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4720;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
