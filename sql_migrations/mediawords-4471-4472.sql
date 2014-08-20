--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4471 and 4472.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4471, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4472, import this SQL file:
--
--     psql mediacloud < mediawords-4471-4472.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


--
-- Controversy traits (boolean properties)
--
CREATE TYPE controversy_trait AS ENUM (

    --
    -- When adding traits here, add them to /root/forms/admin/cm/create_controversy.yml too
    -- (unless you don't want them modified via web UI)
    --

    'controversy_trait_add_bitly_data'  -- For each of the stories in the controversy, fetch
                                        -- Bit.ly click / referrer stats

);
COMMENT ON TYPE controversy_trait
    IS 'Possible controversy traits (use enum.enum_add and enum.enum_del to add / remove properties)';

CREATE TABLE controversy_traits (
    controversy_traits_id   SERIAL PRIMARY KEY,
    controversies_id        INT NOT NULL REFERENCES controversies ON DELETE CASCADE,
    trait                   controversy_trait NOT NULL,
    UNIQUE (controversies_id, trait)
);
COMMENT ON TABLE controversy_traits
    IS 'Controversy traits (boolean properties)';

CREATE UNIQUE INDEX controversy_traits_controversies_id_trait
    ON controversy_traits ( controversies_id, trait );

CREATE RULE controversy_traits_ignore_duplicates AS ON INSERT
    TO controversy_traits
    WHERE EXISTS(
        SELECT 1
        FROM controversy_traits 
        WHERE (controversies_id, trait) = (NEW.controversies_id, NEW.trait)
    )
    DO INSTEAD NOTHING;
COMMENT ON RULE controversy_traits_ignore_duplicates ON controversy_traits
    IS 'Silently skip INSERTing duplicate controvery traits';

CREATE FUNCTION controversy_has_trait(p_controversies_id INT, p_trait controversy_trait)
RETURNS boolean AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM controversy_traits
        WHERE controversies_id = p_controversies_id
          AND trait = p_trait
    ) THEN RETURN TRUE;
    ELSE RETURN FALSE;
    END IF;
END;
$$
LANGUAGE 'plpgsql';
COMMENT ON FUNCTION controversy_has_trait(INT, controversy_trait)
    IS 'Return true if controversy has trait';



CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4472;
    
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
