

ALTER TABLE media_sets_media_map
	ADD COLUMN db_row_last_updated timestamp with time zone default now();

ALTER TABLE media_sets_media_map
	ALTER COLUMN db_row_last_updated SET NOT NULL;

ALTER TABLE stories
	ADD COLUMN db_row_last_updated timestamp with time zone;

ALTER TABLE story_sentences
	ADD COLUMN db_row_last_updated timestamp with time zone;


CREATE OR REPLACE FUNCTION last_updated_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
      -- RAISE NOTICE 'BEGIN ';                                                                                                                            

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') then

      	 NEW.db_row_last_updated = now();

      END IF;

      RETURN NEW;
   END;
$$
LANGUAGE 'plpgsql';

CREATE INDEX media_sets_media_map_db_row_last_updated ON media_sets_media_map ( db_row_last_updated );

CREATE INDEX stories_db_row_last_updated ON stories ( db_row_last_updated );

CREATE INDEX story_sentences_db_row_last_updated ON story_sentences ( db_row_last_updated );

CREATE TRIGGER media_sets_media_map_last_updated_trigger
	BEFORE INSERT OR UPDATE ON media_sets_media_map
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger() ;

CREATE TRIGGER stories_last_updated_trigger
	BEFORE INSERT OR UPDATE ON stories
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger() ;

CREATE TRIGGER story_sentences_last_updated_trigger
	BEFORE INSERT OR UPDATE ON story_sentences
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger() ;

