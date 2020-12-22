--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4759 and 4760.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4759, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4760, import this SQL file:
--
--     psql mediacloud < mediawords-4759-4760.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

TRUNCATE cliff_annotations;
DROP TABLE cliff_annotations;

TRUNCATE nytlabels_annotations;
DROP TABLE nytlabels_annotations;

END;
$$
LANGUAGE 'plpgsql';

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();
