--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4447 and 4448.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4447, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4448, import this SQL file:
--
--     psql mediacloud < mediawords-4447-4448.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

create table media_update_time_queue (
    media_id                    int         not null references media on delete cascade,
    db_row_last_updated         timestamp with time zone not null
);

create index media_update_time_queue_updated on media_update_time_queue ( db_row_last_updated );

drop trigger media_tags_map_update_stories_last_updated_trigger on media_tags_map;
drop trigger media_sets_media_map_update_stories_last_updated_trigger on media_sets_media_map;

alter table controversies 
    add pattern text,
    add solr_seed_query text,
    add solr_seed_query_run boolean,
    add description text;

update controversies c 
    set 
        pattern = a.pattern, 
        solr_seed_query = '"CONTROVERSY CREATED BEFORE SOLR QUERY SUPPORT"',
        solr_seed_query_run = 't',
        description = name || ' in ' || a.media_set_names || ' from ' || a.start_date || ' to ' || a.end_date
    from ( 
            select 
                    ca.controversies_id,
                    min( qss.pattern ) pattern, 
                    string_agg( ms.name, '; ' ) media_set_names, 
                    min( q.start_date ) start_date,
                    min( q.end_date ) end_date
                from controversies ca
                    join query_story_searches qss on ( ca.query_story_searches_id = qss.query_story_searches_id )
                    join queries q on ( qss.queries_id = q.queries_id )
                    join queries_media_sets_map qmsm on ( qmsm.queries_id = q.queries_id )
                    join media_sets ms on ( ms.media_sets_id = qmsm.media_sets_id )
                group by ca.controversies_id
        ) a 
    where a.controversies_id = c.controversies_id;
        
alter table controversies
    alter pattern set not null,
    alter solr_seed_query set not null,
    alter solr_seed_query_run set not null,
    alter description set not null;

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4448;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


