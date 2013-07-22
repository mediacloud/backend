--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4412 and 4413.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4412, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4413, import this SQL file:
--
--     psql mediacloud < mediawords-4412-4413.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4413;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION is_stop_stem(p_size TEXT, p_stem TEXT, p_language TEXT)
    RETURNS BOOLEAN AS \$\$
DECLARE
    result BOOLEAN;
BEGIN

    -- Tiny
    IF p_size = 'tiny' THEN
        IF p_language IS NULL THEN
            SELECT 't' INTO result FROM stopword_stems_tiny
                WHERE stopword_stem = p_stem;
            IF NOT FOUND THEN
                result := 'f';
            END IF;
        ELSE
            SELECT 't' INTO result FROM stopword_stems_tiny
                WHERE stopword_stem = p_stem AND language = p_language;
            IF NOT FOUND THEN
                result := 'f';
            END IF;
        END IF;

    -- Short
    ELSIF p_size = 'short' THEN
        IF p_language IS NULL THEN
            SELECT 't' INTO result FROM stopword_stems_short
                WHERE stopword_stem = p_stem;
            IF NOT FOUND THEN
                result := 'f';
            END IF;
        ELSE
            SELECT 't' INTO result FROM stopword_stems_short
                WHERE stopword_stem = p_stem AND language = p_language;
            IF NOT FOUND THEN
                result := 'f';
            END IF;
        END IF;

    -- Long
    ELSIF p_size = 'long' THEN
        IF p_language IS NULL THEN
            SELECT 't' INTO result FROM stopword_stems_long
                WHERE stopword_stem = p_stem;
            IF NOT FOUND THEN
                result := 'f';
            END IF;
        ELSE
            SELECT 't' INTO result FROM stopword_stems_long
                WHERE stopword_stem = p_stem AND language = p_language;
            IF NOT FOUND THEN
                result := 'f';
            END IF;
        END IF;

    -- unknown size
    ELSE
        RAISE EXCEPTION 'Unknown stopword stem size: "%" (expected "tiny", "short" or "long")', p_size;
        result := 'f';
    END IF;

    RETURN result;
END;
\$\$ LANGUAGE plpgsql;


--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();
