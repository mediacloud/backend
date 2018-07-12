--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4518 and 4519.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4518, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4519, import this SQL file:
--
--     psql mediacloud < mediawords-4518-4519.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table story_sentences add is_dup boolean null;

-- we have to do this in a function to create the partial index on a constant value,
-- which you cannot do with a simple 'create index ... where publish_date > now()'
create or replace function create_initial_story_sentences_dup() RETURNS boolean as $$
declare
    one_month_ago date;
begin
    select now() - interval '1 month' into one_month_ago;

    raise notice 'date: %', one_month_ago;

    execute 'create index story_sentences_dup on story_sentences( md5( sentence ) ) ' ||
        'where week_start_date( publish_date::date ) > ''' || one_month_ago || '''::date';

    return true;
END;
$$ LANGUAGE plpgsql;

select create_initial_story_sentences_dup();

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4519;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
