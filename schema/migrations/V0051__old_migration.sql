


CREATE OR REPLACE FUNCTION last_updated_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
      -- RAISE NOTICE 'BEGIN ';                                                                                                                            

      IF ( story_triggers_enabled() ) AND ( ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') ) then

      	 NEW.db_row_last_updated = now();

      END IF;

      RETURN NEW;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_live_story() returns trigger as $update_live_story$
    begin

        IF NOT story_triggers_enabled() then
	  RETURN NEW;
        END IF;

        update cd.live_stories set
                media_id = NEW.media_id,
                url = NEW.url,
                guid = NEW.guid,
                title = NEW.title,
                description = NEW.description,
                publish_date = NEW.publish_date,
                collect_date = NEW.collect_date,
                full_text_rss = NEW.full_text_rss,
                language = NEW.language,
                db_row_last_updated = NEW.db_row_last_updated
            where
                stories_id = NEW.stories_id;         
        
        return NEW;
    END;
$update_live_story$ LANGUAGE plpgsql;

