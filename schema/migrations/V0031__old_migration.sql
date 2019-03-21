

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

ALTER TABLE media_tags_map
	ADD COLUMN db_row_last_updated timestamp with time zone default now();

ALTER TABLE media_tags_map
	ALTER COLUMN db_row_last_updated SET NOT NULL;

create index media_tags_map_db_row_last_updated on media_tags_map ( db_row_last_updated );

ALTER TABLE stories_tags_map
	ADD COLUMN db_row_last_updated timestamp with time zone default now();

ALTER TABLE stories_tags_map
	ALTER COLUMN db_row_last_updated SET NOT NULL;

CREATE TRIGGER media_tags_last_updated_trigger
	BEFORE INSERT OR UPDATE ON media_tags_map
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger() ;

CREATE TRIGGER stories_tags_map_last_updated_trigger
	BEFORE INSERT OR UPDATE ON stories_tags_map
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger() ;


