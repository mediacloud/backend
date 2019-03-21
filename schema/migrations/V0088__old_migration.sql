


CREATE OR REPLACE FUNCTION update_stories_updated_time_by_stories_id_trigger() RETURNS trigger AS
$$
    DECLARE
        path_change boolean;
        reference_stories_id integer default null;
    BEGIN

        IF TG_OP = 'INSERT' THEN
            -- The "old" record doesn't exist
            reference_stories_id = NEW.stories_id;
        ELSIF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
            reference_stories_id = OLD.stories_id;
        ELSE
            RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;
        END IF;

        UPDATE stories
        SET db_row_last_updated = now()
        WHERE stories_id = reference_stories_id;
	RETURN NULL;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_stories_updated_time_by_media_id_trigger() RETURNS trigger AS
$$
    DECLARE
        path_change boolean;
        reference_media_id integer default null;
    BEGIN

        IF TG_OP = 'INSERT' THEN
            -- The "old" record doesn't exist
            reference_media_id = NEW.media_id;
        ELSIF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
            reference_media_id = OLD.media_id;
        ELSE
            RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;
        END IF;

        UPDATE stories
        SET db_row_last_updated = now()
        WHERE media_id = reference_media_id;

        RETURN NULL;
    END;
$$
LANGUAGE 'plpgsql';

