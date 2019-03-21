

CREATE OR REPLACE FUNCTION update_media_last_updated () RETURNS trigger AS
$$
   DECLARE
   BEGIN

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
      	 update media set db_row_last_updated = now()
             where media_id = NEW.media_id;
      END IF;

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
      	 update media set db_row_last_updated = now()
              where media_id = OLD.media_id;
      END IF;

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
        RETURN NEW;
      ELSE
        RETURN OLD;
      END IF;
   END;
$$
LANGUAGE 'plpgsql';




