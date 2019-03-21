

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
DROP index media_tags_map_db_row_last_updated;

alter table media_tags_map drop column db_row_last_updated CASCADE;

DROP TRIGGER IF EXISTS media_sets_media_map_last_updated_trigger on media_sets_media_map CASCADE;

DROP INDEX media_sets_media_map_db_row_last_updated ;

alter table media_sets_media_map drop db_row_last_updated CASCADE;

DROP TRIGGER IF EXISTS msmm_last_updated on media_sets_media_map CASCADE;
CREATE TRIGGER msmm_last_updated BEFORE INSERT OR UPDATE OR DELETE 
    ON media_sets_media_map FOR EACH ROW EXECUTE PROCEDURE update_media_last_updated() ;

DROP TRIGGER IF EXISTS mtm_last_updated on media_tags_map CASCADE;
CREATE TRIGGER mtm_last_updated BEFORE INSERT OR UPDATE OR DELETE 
    ON media_tags_map FOR EACH ROW EXECUTE PROCEDURE update_media_last_updated() ;





