CREATE INDEX CONCURRENTLY relative_file_paths_to_verify on downloads( relative_file_path ) where file_status = 'tbd' and relative_file_path <> 'tbd' and relative_file_path <> 'error';
