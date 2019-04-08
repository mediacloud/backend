--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4717 and 4718.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4717, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4718, import this SQL file:
--
--     psql mediacloud < mediawords-4717-4718.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--


create or replace function get_downloads_for_queue() returns table(downloads_id bigint) as $$
declare
    pending_host record;
begin
    create temporary table pending_downloads (downloads_id bigint) on commit drop;
    for pending_host in
            WITH RECURSIVE t AS (
               (SELECT host FROM downloads_pending ORDER BY host LIMIT 1)
               UNION ALL
               SELECT (SELECT host FROM downloads_pending WHERE host > t.host ORDER BY host LIMIT 1)
               FROM t
               WHERE t.host IS NOT NULL
               )
            SELECT host FROM t WHERE host IS NOT NULL
        loop
            insert into pending_downloads
                select dp.downloads_id
                    from downloads_pending dp
                    where host = pending_host.host
                    order by priority, downloads_id desc nulls last
                    limit 1;
        end loop;

    return query select pd.downloads_id from pending_downloads pd;
 end;

$$ language plpgsql;

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4718;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


