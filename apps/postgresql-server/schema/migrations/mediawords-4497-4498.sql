--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4497 and 4498.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4497, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4498, import this SQL file:
--
--     psql mediacloud < mediawords-4497-4498.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

DROP INDEX media_sets_cluster;

ALTER TABLE media_sets
	DROP CONSTRAINT dashboard_media_sets_type;

ALTER TABLE media_sets
	DROP COLUMN media_clusters_id;

ALTER TABLE dashboard_media_sets
	DROP COLUMN media_cluster_runs_id;


DROP TABLE media_cluster_words;

DROP TABLE media_cluster_zscores;

DROP TABLE media_clusters_media_map;

DROP TABLE media_cluster_map_poles;

DROP TABLE media_cluster_map_pole_similarities;

DROP TABLE media_clusters;

DROP TABLE media_cluster_maps;

DROP TABLE media_cluster_links;

DROP TABLE media_cluster_runs;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4498;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

ALTER TABLE media_sets
	ADD CONSTRAINT dashboard_media_sets_type check ( ( ( set_type = 'medium' ) and ( media_id is not null ) )
        or
        ( ( set_type = 'collection' ) and ( tags_id is not null ) )
        or
        ( ( set_type = 'cluster' ) ) );

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

