--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4460 and 4461.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4460, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4461, import this SQL file:
--
--     psql mediacloud < mediawords-4460-4461.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

create table solr_import_stories (
    stories_id          int not null references stories on delete cascade
);

create index solr_import_stories_story on solr_import_stories ( stories_id );

alter table media add db_row_last_updated timestamp with time zone;
create index media_db_row_last_updated on media( db_row_last_updated );
    
create temporary view mtm_last_updated as
    select media_id, max( db_row_last_updated ) db_row_last_updated
        from media_tags_map mtm group by mtm.media_id;

create temporary view msmm_last_updated as
    select media_id, max( db_row_last_updated ) db_row_last_updated
        from media_sets_media_map msmm group by msmm.media_id;
    
update media m set db_row_last_updated = mtm.db_row_last_updated 
    from mtm_last_updated mtm where m.media_id = mtm.media_id;

update media m set db_row_last_updated = msmm.db_row_last_updated 
    from msmm_last_updated msmm
    where m.media_id = msmm.media_id and 
        msmm.db_row_last_updated > m.db_row_last_updated;
    
CREATE OR REPLACE FUNCTION update_media_last_updated () RETURNS trigger AS
$$
   DECLARE
   BEGIN

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
      	 update media set db_row_last_updated = now() where media_id = NEW.media_id;
      END IF;
      
      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
      	 update media set db_row_last_updated = now() where media_id = OLD.media_id;
      END IF;

      RETURN NEW;
   END;
$$
LANGUAGE 'plpgsql';


DROP TRIGGER IF EXISTS media_tags_map_last_updated_trigger on media_tags_map CASCADE;
drop trigger if exists media_tags_last_updated_trigger on media_tags_map;

alter table media_tags_map drop db_row_last_updated;

DROP TRIGGER IF EXISTS media_sets_media_map_last_updated_trigger on media_sets_media_map CASCADE;

alter table media_sets_media_map drop db_row_last_updated;

DROP TRIGGER IF EXISTS msmm_last_updated on media_sets_media_map CASCADE;
CREATE TRIGGER msmm_last_updated BEFORE INSERT OR UPDATE OR DELETE 
    ON media_sets_media_map FOR EACH ROW EXECUTE PROCEDURE update_media_last_updated() ;

DROP TRIGGER IF EXISTS mtm_last_updated on media_tags_map CASCADE;
CREATE TRIGGER mtm_last_updated BEFORE INSERT OR UPDATE OR DELETE 
    ON media_tags_map FOR EACH ROW EXECUTE PROCEDURE update_media_last_updated() ;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4461;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


