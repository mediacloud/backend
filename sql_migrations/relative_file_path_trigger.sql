CREATE OR REPLACE FUNCTION download_relative_file_path_trigger() RETURNS trigger AS 
$$
   DECLARE
      path_change boolean;
   BEGIN
      -- RAISE NOTICE 'BEGIN ';
      IF TG_OP = 'UPDATE' then
          -- RAISE NOTICE 'UPDATE ';

	  -- The second part is needed because of the way comparisons with null are handled.
	  path_change := ( OLD.path <> NEW.path )  AND (  ( OLD.path is not null) <> (NEW.path is not null) ) ;
	  -- RAISE NOTICE 'test result % ', path_change; 
	  
          IF path_change is null THEN
	       -- RAISE NOTICE 'Path change % != %', OLD.path, NEW.path;
               NEW.relative_file_path = get_relative_file_path(NEW.path);
	  ELSE
               -- RAISE NOTICE 'NO path change % = %', OLD.path, NEW.path;
          END IF;
      ELSIF TG_OP = 'INSERT' then
	  NEW.relative_file_path = get_relative_file_path(NEW.path);
      END IF;

      RETURN NEW;
   END;
$$ 
LANGUAGE 'plpgsql';

DROP TRIGGER IF EXISTS download_relative_file_path_trigger on downloads CASCADE;
CREATE TRIGGER download_relative_file_path_trigger BEFORE INSERT OR UPDATE ON downloads FOR EACH ROW EXECUTE PROCEDURE  download_relative_file_path_trigger() ;
