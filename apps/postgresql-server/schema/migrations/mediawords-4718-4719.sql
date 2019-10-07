--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4718 and 4719.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4718, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4719, import this SQL file:
--
--     psql mediacloud < mediawords-4718-4719.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

-- efficiently query downloads_pending for the latest downloads_id per host.  postgres is not able to do this through
-- its normal query planning (it just does an index scan of the whole indesx).  this turns a query that 
-- takes ~22 seconds for a 100 million row table into one that takes ~0.25 seconds
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
                        left join queued_downloads qd on ( dp.downloads_id = qd.downloads_id )
                    where 
                        host = pending_host.host and
                        qd.downloads_id is null
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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4719;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


