--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4509 and 4510.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4509, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4510, import this SQL file:
--
--     psql mediacloud < mediawords-4509-4510.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Helper to find corrupted sequences (the ones in which the primary key's sequence value > MAX(primary_key))
CREATE OR REPLACE FUNCTION find_corrupted_sequences()
RETURNS TABLE(tablename VARCHAR, maxid BIGINT, sequenceval BIGINT)
AS $BODY$
DECLARE
    r RECORD;
BEGIN

    SET client_min_messages TO WARNING;
    DROP TABLE IF EXISTS temp_corrupted_sequences;
    CREATE TEMPORARY TABLE temp_corrupted_sequences (
        tablename VARCHAR NOT NULL UNIQUE,
        maxid BIGINT,
        sequenceval BIGINT
    ) ON COMMIT DROP;
    SET client_min_messages TO NOTICE;

    FOR r IN (

        -- Get all tables, their primary keys and serial sequence names
        SELECT t.relname AS tablename,
               primarykey AS idcolumn,
               pg_get_serial_sequence(t.relname, primarykey) AS serialsequence
        FROM pg_constraint AS c
            JOIN pg_class AS t ON c.conrelid = t.oid
            JOIN pg_namespace nsp ON nsp.oid = t.relnamespace
            JOIN (
                SELECT a.attname AS primarykey,
                       i.indrelid
                FROM pg_index AS i
                    JOIN pg_attribute AS a
                        ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
                WHERE i.indisprimary
            ) AS pkey ON pkey.indrelid = t.relname::regclass
        WHERE conname LIKE '%_pkey'
          AND nsp.nspname = 'public'
          AND t.relname NOT IN (
            'story_similarities_100_short',
            'url_discovery_counts'
          )
        ORDER BY t.relname

    )
    LOOP

        -- Filter out the tables that have their max ID bigger than the last
        -- sequence value
        EXECUTE '
            INSERT INTO temp_corrupted_sequences
                SELECT tablename,
                       maxid,
                       sequenceval
                FROM (
                    SELECT ''' || r.tablename || ''' AS tablename,
                           MAX(' || r.idcolumn || ') AS maxid,
                           ( SELECT last_value FROM ' || r.serialsequence || ') AS sequenceval
                    FROM ' || r.tablename || '
                ) AS id_and_sequence
                WHERE maxid > sequenceval
        ';

    END LOOP;

    RETURN QUERY SELECT * FROM temp_corrupted_sequences ORDER BY tablename;

END
$BODY$
LANGUAGE 'plpgsql';



CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4510;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

