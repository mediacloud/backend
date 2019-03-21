


-- Update "db_row_last_updated" column to trigger Solr (re)imports for given
-- row; no update gets done if "db_row_last_updated" is set explicitly in
-- INSERT / UPDATE (e.g. when copying between tables)
CREATE OR REPLACE FUNCTION last_updated_trigger() RETURNS trigger AS $$

BEGIN

    IF TG_OP = 'INSERT' THEN
        IF NEW.db_row_last_updated IS NULL THEN
            NEW.db_row_last_updated = NOW();
        END IF;

    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.db_row_last_updated = OLD.db_row_last_updated THEN
            NEW.db_row_last_updated = NOW();
        END IF;
    END IF;

    RETURN NEW;

END;

$$ LANGUAGE 'plpgsql';




