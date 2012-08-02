
CREATE TYPE download_file_status AS ENUM ( 'tbd', 'missing', 'na', 'present', 'inline', 'redownloaded', 'error_redownloading' );

ALTER TABLE downloads ADD COLUMN file_status download_file_status not null default 'tbd';

ALTER TABLE downloads ADD COLUMN relative_file_path text not null default 'tbd';


ALTER TABLE downloads ADD COLUMN old_download_time timestamp without time zone;
ALTER TABLE downloads ADD COLUMN old_state download_state;
UPDATE downloads set old_download_time = download_time, old_state = state;

CREATE UNIQUE INDEX downloads_file_status on downloads(file_status, downloads_id);
CREATE UNIQUE INDEX downloads_relative_path on downloads( relative_file_path, downloads_id);

CREATE OR REPLACE FUNCTION get_relative_file_path(path text)
    RETURNS text AS
$$
DECLARE
    regex_tar_format text;
    relative_file_path text;
BEGIN
    IF path is null THEN
       RETURN 'na';
    END IF;

    regex_tar_format :=  E'tar\\:\\d*\\:\\d*\\:(mediacloud-content-\\d*\.tar).*';

    IF path ~ regex_tar_format THEN
         relative_file_path =  regexp_replace(path, E'tar\\:\\d*\\:\\d*\\:(mediacloud-content-\\d*\.tar).*', E'\\1') ;
    ELSIF  path like 'content:%' THEN 
         relative_file_path =  'inline';
    ELSEIF path like 'content/%' THEN
         relative_file_path =  regexp_replace(path, E'content\\/', E'\/') ;
    ELSE  
         relative_file_path = 'error';
    END IF;

--  RAISE NOTICE 'relative file path for %, is %', path, relative_file_path;

    RETURN relative_file_path;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE
  COST 10;

