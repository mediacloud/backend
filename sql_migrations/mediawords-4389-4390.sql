--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4389 and 4390.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4389, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4390, import this SQL file:
--
--     psql mediacloud < mediawords-4389-4390.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

-- no-op

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

