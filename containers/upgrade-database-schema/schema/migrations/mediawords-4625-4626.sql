--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4625 and 4626.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4625, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4626, import this SQL file:
--
--     psql mediacloud < mediawords-4625-4626.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Upsert helper to INSERT or UPDATE an object to object cache
CREATE OR REPLACE FUNCTION cache.upsert_cache_object (
    param_table_name VARCHAR,
    param_object_id BIGINT,
    param_raw_data BYTEA
) RETURNS VOID AS
$$
DECLARE
    _cache_object_found INT;
BEGIN

    LOOP
        -- Try UPDATing
        EXECUTE '
            UPDATE ' || param_table_name || '
            SET raw_data = $2
            WHERE object_id = $1
            RETURNING *
        ' INTO _cache_object_found
          USING param_object_id, param_raw_data;

        IF _cache_object_found IS NOT NULL THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN

            EXECUTE '
                INSERT INTO ' || param_table_name || ' (object_id, raw_data)
                VALUES ($1, $2)
            ' USING param_object_id, param_raw_data;

            RETURN;

        EXCEPTION WHEN UNIQUE_VIOLATION THEN
            -- If someone else INSERTs the same key concurrently,
            -- we will get a unique-key failure. In that case, do
            -- nothing and loop to try the UPDATE again.
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4626;

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

