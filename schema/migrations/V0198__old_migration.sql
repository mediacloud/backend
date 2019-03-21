

ALTER TABLE story_sentences
	ADD COLUMN last_updated timestamp with time zone NOT NULL DEFAULT now();

ALTER TABLE story_sentences
        ALTER COLUMN last_updated DROP DEFAULT;

CREATE OR REPLACE FUNCTION story_sentences_last_updated_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
      -- RAISE NOTICE 'BEGIN ';                                                                                                                            

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') then

      	 NEW.last_updated = now();
      ELSE
               -- RAISE NOTICE 'NO path change % = %', OLD.path, NEW.path;                                                                                  
      END IF;

      RETURN NEW;
   END;
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER story_sentences_last_updated_trigger
	BEFORE INSERT OR UPDATE ON story_sentences
	FOR EACH ROW
	EXECUTE PROCEDURE story_sentences_last_updated_trigger() ;

create table controversy_ignore_redirects (
    controversy_ignore_redirects_id     serial primary key,
    url                                 varchar( 1024 )
);

create index controversy_ignore_redirects_url on controversy_ignore_redirects ( url );




